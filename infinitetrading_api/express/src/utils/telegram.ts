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
export function notifyTelegram(text: string, chatId?: string): void {
  void notifyTelegramOrThrow(text, chatId).catch(err => {
    console.log('[telegram] notification failed (non-fatal):', err?.message || err);
  });
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
 * Formats and sends an API-activity line in the same style the R handlers used:
 *   "<status> <endpoint> invoked apiKey: <masked> / pool: ... / response: ..."
 * Keeping the shape identical means existing Telegram-based ops habits and any
 * downstream log scraping continue to work after the migration.
 */
export function notifyApiActivity(params: {
  status: string;
  endpoint: string;
  apiKey?: string;
  fields?: Record<string, unknown>;
  response?: unknown;
}): void {
  const { status, endpoint, apiKey, fields = {}, response } = params;
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
