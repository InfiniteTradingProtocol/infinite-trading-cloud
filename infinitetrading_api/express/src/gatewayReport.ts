/**
 * gatewayReport.ts — restores the gateway's live Telegram request feed.
 *
 * WHY: the retired R gateway called send_request_report() (plumber/reporting.R)
 * on every request, giving a live feed of inbound calls and their outcomes in a
 * dedicated Telegram group. That feed was the main way of seeing "what is going
 * on right now" without SSHing in. The Express migration dropped it, so the
 * channel went silent.
 *
 * This middleware reproduces it, keeping the original message layout so the
 * channel reads exactly as before.
 *
 * DIFFERENCES FROM THE R VERSION (all deliberate):
 *
 *  1. SECRETS ARE MASKED PROPERLY. The R version masked `apiKey` but then
 *     printed every remaining parameter verbatim under "Other". Any request
 *     carrying a privateKey (getNewApiKey) therefore published a live wallet
 *     secret to Telegram. Here every parameter is run through a redactor:
 *     secret-bearing names are dropped entirely, api keys are masked, and the
 *     body is covered as well as the query string (the R gateway only ever saw
 *     query strings).
 *
 *  2. IT REPORTS THE RESPONSE, NOT JUST THE REQUEST. R reported inbound
 *     requests; the status code was passed in by hand at each call site. Here a
 *     single `finish` hook captures the real status and duration for every
 *     route, so inbound and outbound are both visible with no per-route wiring.
 *
 *  3. IT IS PACED. Telegram throttles per-chat bursts at roughly one message
 *     per second and returns 429 for the rest. Delivery pacing lives in
 *     utils/telegram.ts so every producer shares one budget; this module just
 *     hands over the formatted line.
 *
 *  4. NOISE IS FILTERED. Health checks, docs and scanner 404s would otherwise
 *     drown the signal.
 *
 *  5. ONE MESSAGE PER REQUEST. Several handlers already called
 *     notifyApiActivity() to announce their own outcome. Now that every
 *     request is reported here, those would be a second, near-identical
 *     message for the same call. Instead a handler attaches its detail via
 *     attachReportDetail() and it is folded into this single report, so the
 *     richer per-endpoint context is kept without duplicating the message.
 */

import { Request, Response, NextFunction } from 'express';
import { notifyTelegram, maskApiKey } from './utils/telegram';

/** Parameters whose values must never reach Telegram, matched case-insensitively. */
const SECRET_PARAMS = /^(privateKey|private_key|pKey|pkey|secret|password|mnemonic|seed|token)$/i;

/** Parameters that are API keys: shown, but masked. */
const API_KEY_PARAMS = /^(apiKey|api_key)$/i;

/**
 * Paths that would flood the channel without saying anything useful.
 * getAllYields is a high-frequency frontend poll (~280 calls/day, far more than
 * everything else combined) and carries no operator signal.
 */
const IGNORED_PATHS = [
  /^\/?$/,
  /^\/(favicon\.ico|robots\.txt)$/,
  /^\/__docs__/,
  /^\/openapi\.json$/,
  /^\/llmIntrospect$/,
  /^\/getAllYields$/,
];

/**
 * The dedicated gateway group. Falls back to TG_CHAT_ID so a missing variable
 * degrades to "reports land in the default chat" rather than silence.
 */
function gatewayChatId(): string | undefined {
  return process.env.TG_GATEWAY_CHAT_ID || process.env.TG_CHAT_ID;
}

/** Redacts one parameter for display. Returns null if it must be omitted. */
function redact(name: string, value: unknown): string | null {
  if (SECRET_PARAMS.test(name)) return '[REDACTED]';
  if (API_KEY_PARAMS.test(name)) {
    const s = String(value);
    return s ? maskApiKey(s) : null;
  }
  const s = String(value);
  if (s === '') return null;
  // A bare 64-hex value is a private key regardless of the parameter name.
  if (/^(0x)?[0-9a-fA-F]{64}$/.test(s)) return '[REDACTED]';
  return s.length > 80 ? `${s.slice(0, 77)}...` : s;
}

/**
 * Removes secrets from free-form text such as a response body, where they are
 * not attached to a known parameter name. getNewApiKey, for instance, returns a
 * freshly minted API key in its body.
 */
function scrubSecrets(text: string): string {
  return text
    .replace(/(0x)?[0-9a-fA-F]{64}/g, '[REDACTED]')
    .replace(
      /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g,
      m => maskApiKey(m)
    );
}

function methodEmoji(method: string): string {
  switch (method.toUpperCase()) {
    case 'GET': return '🟦 GET';
    case 'POST': return '🟩 POST';
    case 'PUT': return '🟨 PUT';
    case 'PATCH': return '🟧 PATCH';
    case 'DELETE': return '🟥 DELETE';
    case 'HEAD': return '⬜ HEAD';
    case 'OPTIONS': return '🟪 OPTIONS';
    default: return `⬜ ${method}`;
  }
}

function statusEmoji(status: number): string {
  if (!Number.isFinite(status) || status < 200) return '⬜️';
  if (status < 300) return '✅';
  if (status < 400) return '⚠️';
  if (status < 500) return '❗';
  return '🔥';
}

/**
 * Extra detail a handler wants included in its request's report.
 * Stored on the response object so it lives exactly as long as the request.
 */
const DETAIL_KEY = '__gatewayReportDetail';

export interface ReportDetail {
  outcome?: string;
  response?: unknown;
  fields?: Record<string, unknown>;
}

/**
 * Attach handler-specific detail to the report for the current request.
 * Called by endpoints that previously sent their own Telegram message; the
 * detail is merged into the single report emitted when the response finishes.
 */
export function attachReportDetail(res: Response, detail: ReportDetail): void {
  const existing: ReportDetail = (res as any)[DETAIL_KEY] || {};
  (res as any)[DETAIL_KEY] = {
    outcome: detail.outcome ?? existing.outcome,
    response: detail.response ?? existing.response,
    fields: { ...(existing.fields || {}), ...(detail.fields || {}) },
  };
}

export function gatewayReportMiddleware(req: Request, res: Response, next: NextFunction): void {
  const path = req.path || '/';
  if (IGNORED_PATHS.some(re => re.test(path))) return next();
  if (process.env.TG_GATEWAY_REPORTS === 'off') return next();

  const startedAt = Date.now();

  res.on('finish', () => {
    try {
      // Merge query and body: unlike the R gateway, POST bodies are visible.
      const params: Record<string, unknown> = { ...(req.query as any), ...(req.body as any) };

      const main = ['network', 'protocol', 'pool', 'apiKey'];
      const get = (k: string) => {
        const v = params[k];
        return v === undefined || v === '' ? 'None' : (redact(k, v) ?? 'None');
      };

      const others = Object.keys(params)
        .filter(k => !main.includes(k))
        .map(k => {
          const r = redact(k, params[k]);
          return r === null ? null : `${k}: ${r}`;
        })
        .filter(Boolean);

      const ip = (req.headers['x-real-ip'] as string) || req.ip || '0.0.0.0';
      const status = res.statusCode;
      const ms = Date.now() - startedAt;
      const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
      const endpoint = path.replace(/^\/+/, '');

      const detail: ReportDetail | undefined = (res as any)[DETAIL_KEY];

      // A handler's own outcome is more precise than the HTTP status: these
      // endpoints return 200 with {"status":"fail"} in the body.
      const outcomeLine = detail?.outcome ? ` [${detail.outcome}]` : '';

      for (const [k, v] of Object.entries(detail?.fields || {})) {
        const r = redact(k, v);
        if (r !== null && !main.includes(k)) others.push(`${k}: ${r}`);
      }

      let responseLine = '';
      if (detail?.response !== undefined && detail.response !== null) {
        const raw = typeof detail.response === 'string'
          ? detail.response
          : JSON.stringify(detail.response);
        responseLine = `\n📬 Response: ${scrubSecrets(String(raw)).substring(0, 400)}`;
      }

      const msg =
        `${ts} ${statusEmoji(status)} ${methodEmoji(req.method)} /${endpoint} → ${status}${outcomeLine} (${ms}ms)\n` +
        `🌎 Network: ${get('network')}\n` +
        `🔧 Protocol: ${get('protocol')}\n` +
        `⚫ Pool: ${get('pool')}\n` +
        `🔑 API Key: ${get('apiKey')}\n` +
        `📄 Other: ${others.length ? others.join(' / ') : 'none'}\n` +
        `🌐 IP: ${ip}` + responseLine;

      // notifyTelegram queues and paces delivery (see utils/telegram.ts), so a
      // burst of requests is spread out rather than rejected by Telegram.
      notifyTelegram(msg, gatewayChatId());
    } catch (err: any) {
      // Reporting must never affect the response it is describing.
      console.log('[gatewayReport] failed (non-fatal):', err?.message || err);
    }
  });

  next();
}
