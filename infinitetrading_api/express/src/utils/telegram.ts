/**
 * telegram.ts — Node port of infinitetrading/src/telegram.R's send_telegram_text().
 *
 * WHY: the R API handlers (lend/repay/borrow/unlend/vaultTrade/... in api.R)
 * each called send_telegram_text(msg) after completing, giving operators a live
 * feed of API activity and failures in Telegram. As those endpoints were
 * migrated to Express that notification channel was silently lost. This module
 * restores it so the migrated service has the same operational visibility the R
 * service had.
 *
 * Parity notes vs the R implementation:
 *  - Same Bot API endpoint (https://api.telegram.org/bot<token>/sendMessage)
 *    and same form-encoded {chat_id, text} body.
 *  - Same env vars: TG_BOT (bot token) and TG_CHAT_ID (default chat).
 *  - DIFFERENCE (deliberate): R called stop_for_status(), so a Telegram outage
 *    would raise an error inside the handler. Here notification failures are
 *    swallowed and logged instead — a monitoring channel being down must never
 *    fail a live trading request. Use notifyTelegramOrThrow() if a caller
 *    genuinely needs delivery confirmation.
 *
 * PACING: Telegram throttles each chat at roughly one message per second and
 * answers 429 for the rest, so anything sent in a burst is simply lost. Every
 * fire-and-forget send therefore goes through one shared per-chat queue that
 * spaces messages out and obeys the `retry_after` value Telegram returns.
 * Keeping the queue here rather than in a single caller means all producers
 * (the gateway request feed, mint notifications, business alerts) share one
 * budget instead of competing for it.
 */

const TELEGRAM_TIMEOUT_MS = 8000;

function creds(): { token: string; chatId: string } | null {
  const token = process.env.TG_BOT;
  const chatId = process.env.TG_CHAT_ID;
  if (!token || !chatId) return null;
  return { token, chatId };
}

/**
 * Send a Telegram message. Never throws and never blocks the caller's response:
 * failures (missing creds, network error, Telegram 4xx/5xx) are logged only.
 */
const SEND_INTERVAL_MS = 1200;
/** Bounded so a traffic spike cannot grow memory or lag minutes behind. */
const MAX_QUEUE_PER_CHAT = 60;

interface ChatQueue {
  pending: string[];
  timer: NodeJS.Timeout | null;
  dropped: number;
}
const queues = new Map<string, ChatQueue>();

function queueFor(chatId: string): ChatQueue {
  let q = queues.get(chatId);
  if (!q) {
    q = { pending: [], timer: null, dropped: 0 };
    queues.set(chatId, q);
  }
  return q;
}

async function drain(chatId: string): Promise<void> {
  const q = queueFor(chatId);
  const next = q.pending.shift();

  if (next !== undefined) {
    try {
      await notifyTelegramOrThrow(next, chatId);
    } catch (err: any) {
      const msg = String(err?.message || err);
      // Telegram tells us exactly how long to wait; requeue and honour it
      // instead of burning the message.
      const m = msg.match(/retry after (\d+)/i);
      if (m && q.pending.length < MAX_QUEUE_PER_CHAT) {
        q.pending.unshift(next);
        if (q.timer) { clearInterval(q.timer); q.timer = null; }
        setTimeout(() => startDraining(chatId), (Number(m[1]) + 1) * 1000).unref?.();
        return;
      }
      console.log('[telegram] notification failed (non-fatal):', msg);
    }
  }

  if (q.pending.length === 0) {
    if (q.dropped > 0) {
      const n = q.dropped;
      q.dropped = 0;
      q.pending.push(`🔇 ${n} further notification(s) dropped (queue full).`);
    } else if (q.timer) {
      clearInterval(q.timer);
      q.timer = null;
    }
  }
}

function startDraining(chatId: string): void {
  const q = queueFor(chatId);
  if (q.timer) return;
  q.timer = setInterval(() => { void drain(chatId); }, SEND_INTERVAL_MS);
  // Never keep the process alive just to flush notifications.
  q.timer.unref?.();
  void drain(chatId);
}

/**
 * Queue a Telegram message for paced delivery. Never throws and never blocks
 * the caller's response.
 */
export function notifyTelegram(text: string, chatId?: string): void {
  const target = chatId || process.env.TG_CHAT_ID;
  if (!target) {
    console.log('[telegram] TG_CHAT_ID not configured; message dropped.');
    return;
  }
  const q = queueFor(target);
  if (q.pending.length >= MAX_QUEUE_PER_CHAT) {
    q.dropped++;
    return;
  }
  q.pending.push(text);
  startDraining(target);
}

/** Same as notifyTelegram but awaitable and rejects on failure. */
export async function notifyTelegramOrThrow(text: string, chatId?: string): Promise<void> {
  const c = creds();
  if (!c) {
    throw new Error('TG_BOT / TG_CHAT_ID not configured');
  }
  const url = `https://api.telegram.org/bot${c.token}/sendMessage`;
  const body = new URLSearchParams({ chat_id: chatId || c.chatId, text });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TELEGRAM_TIMEOUT_MS);
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
      signal: controller.signal,
    });
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`Telegram API ${resp.status}: ${detail.substring(0, 200)}`);
    }
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Records the outcome of an API call for operator visibility.
 *
 * ORIGINALLY this sent its own Telegram message, mirroring the R handlers.
 * Since gatewayReport.ts now reports *every* request, doing that would post a
 * second, near-identical message about the same call. So when a response object
 * is supplied the detail is folded into that request's single report instead.
 *
 * Without a response object (background jobs with no request in flight) it
 * still sends standalone, since there is no report to attach to.
 */
export function notifyApiActivity(params: {
  status: string;
  endpoint: string;
  apiKey?: string;
  fields?: Record<string, unknown>;
  response?: unknown;
  res?: any;
}): void {
  const { status, endpoint, apiKey, fields = {}, response, res } = params;

  if (res) {
    // Deferred import: gatewayReport imports this module, so requiring it at
    // load time would create a circular import.
    const { attachReportDetail } = require('../gatewayReport');
    attachReportDetail(res, { outcome: status, response, fields });
    return;
  }

  const parts = [`${status} ${endpoint} invoked`];
  if (apiKey) parts.push(`apiKey: ${maskApiKey(apiKey)}`);
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined || v === null || v === '') continue;
    parts.push(`${k}: ${v}`);
  }
  if (response !== undefined && response !== null) {
    const r = typeof response === 'string' ? response : JSON.stringify(response);
    parts.push(`response: ${String(r).substring(0, 400)}`);
  }
  notifyTelegram(parts.join(' / '));
}

/** Port of R's mask_api(): show only the head/tail of a key in logs. */
export function maskApiKey(apiKey: string): string {
  if (!apiKey || apiKey.length < 12) return '***';
  return `${apiKey.substring(0, 6)}...${apiKey.substring(apiKey.length - 4)}`;
}
