/**
 * requests/cexPublic.ts — Node port of the eight public CEX endpoints that
 * were served by the R gateway (port 8003,
 * infinitetrading/src/api/gateway/endpoints/*.R) proxying to plumber-api
 * (port 8002, infinitetrading/src/api/api.R ~lines 306-867):
 *
 *   POST   /registerCEXSubaccount   POST   /setCEXSide
 *   GET    /getCEXSide              POST   /setCEXStrategy
 *   DELETE /deleteCEXBot            POST   /deactivateCEXBot
 *   DELETE /deleteCEXSubaccount     GET    /getAllCEXSubaccounts
 *
 * Each handler combines BOTH R layers: the gateway supplied the
 * sanitization/validation contract, api.R supplied the actual behaviour.
 *
 * ===========================================================================
 * *** PRODUCTION CRASH BUG FIXED (flagged per migration rules) ***
 *
 * SIX of these eight endpoints (registerCEXSubaccount, setCEXSide, getCEXSide,
 * setCEXStrategy, deleteCEXBot, deactivateCEXBot) called
 * `encrypt_gas_wallet_api_key()` in api.R, a function that is DEFINED NOWHERE.
 * In live production every one of them returned
 *   {"status":["fail"],"status_code":[500],
 *    "message":["Error: could not find function \"encrypt_gas_wallet_api_key\""]}
 * (reproduced against both :8002 and :8003 before this port, and visible in the
 * gateway logs since at least 2026-08-27). Consequently `cex_subaccounts` and
 * `cex_bots` are both EMPTY, so no stored data constrains the encoding.
 *
 * A crash-bug is fixed rather than replicated. The replacement is
 * `gasWalletApiKeyToken()` in utils/cexCrypto.ts — a deterministic keyed HMAC
 * lookup token, which is what the column's usage requires (it is written on
 * register and then equality-matched on every read; a random-IV encryption
 * could never have matched). Full rationale in that file's header.
 *
 * The two signature-authenticated endpoints (deleteCEXSubaccount,
 * getAllCEXSubaccounts) did NOT touch that function and worked; they are
 * ported behaviour-for-behaviour.
 * ===========================================================================
 *
 * WIRE FORMAT: plumber's serializer_json() boxes scalars as 1-element arrays
 * ({"status":["fail"],"status_code":[500],...}) and serializes an R NULL held
 * inside a named list as {} (both verified live). `box()` / `RNull` below
 * reproduce that exactly, consistent with the already-migrated endpoints.
 *
 * SQL: R interpolated values into query strings with sprintf(). This port uses
 * parameterised queries throughout — a pure hardening of the transport with no
 * observable behavioural difference (see SECURITY note on `pair` below).
 *
 * SWAGGER: /getAllCEXSubaccounts and /setCEXStrategy are in R's
 * `hidden_endpoints` (api/helpers/endpoints.R) and so carry no @openapi block.
 */

import { Router, Request, Response } from 'express';
import { dbQuery, dbExecute } from '../db';
import { isValidAPIKey } from '../basicCheck';
import { gasWalletApiKeyToken, encryptCexCredential } from '../utils/cexCrypto';
import { getCexBalanceDetails } from '../utils/cexBalance';
import { notifyApiActivity } from '../utils/telegram';

const router = Router();

const EXPRESS_BASE = process.env.EXPRESS_INTERNAL_URL || 'http://localhost:8000/';
const SIGNATURE_MESSAGE =
  'Sign this message to authenticate with dHEDGE Gas Wallet Manager.\n\nThis signature will be used to verify your identity for secure operations.';

/** Sentinel for an R NULL nested inside a list — jsonlite renders it as {}. */
const RNull = {};

/** plumber serializer_json() scalar boxing. */
function box<T>(v: T): [T] {
  return [v];
}

function fail(status_code: number, message: string) {
  return { status: box('fail'), status_code: box(status_code), message: box(message) };
}

/** Read a param from query or body, matching plumber (which merged both). */
function param(req: Request, name: string): string | undefined {
  const q: any = req.query;
  const b: any = req.body || {};
  const v = q[name] !== undefined ? q[name] : b[name];
  return v === undefined || v === null ? undefined : String(v);
}

// ---------------------------------------------------------------------------
// Gateway-layer sanitizers (ported verbatim from the endpoints/*.R shims).
// ---------------------------------------------------------------------------

/** gsub("[^a-zA-Z0-9_ -]", "", subaccount_name) */
function sanitizeSubaccountName(v: string): string {
  return v.replace(/[^a-zA-Z0-9_ -]/g, '');
}

/**
 * gsub("[^A-Z0-9/-]", "", toupper(pair))
 * SECURITY: this is also what keeps `pair` free of quote characters. It is
 * retained (not relaxed) even though this port additionally parameterises SQL.
 */
function sanitizePair(v: string): string {
  return v.toUpperCase().replace(/[^A-Z0-9/-]/g, '');
}

/** gsub("[^a-zA-Z]", "", tolower(exchange)) */
function sanitizeExchange(v: string): string {
  return v.toLowerCase().replace(/[^a-zA-Z]/g, '');
}

/** Port of R's is_signature_format_valid(). */
function isSignatureFormatValid(sig: unknown): boolean {
  return typeof sig === 'string' && /^0x[0-9a-fA-F]{130,}$/.test(sig);
}

/** Port of R's verifySignature() — delegates to Express's own /verifySignature. */
async function verifySignatureViaExpress(signature: string, manager: string): Promise<boolean> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}verifySignature`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: SIGNATURE_MESSAGE, signature, expectedAddress: manager }),
    });
    const data: any = await resp.json();
    return resp.status === 200 && data.status === 'success' && !!data.isValid;
  } catch {
    return false;
  }
}

/** Port of R's getWallet(apiKey) — resolves an API token to its bound EOA. */
async function getWalletForApiKey(apiKey: string): Promise<string | null> {
  try {
    const resp = await fetch(`${EXPRESS_BASE}getWallet?apiKey=${encodeURIComponent(apiKey)}`);
    if (resp.status !== 200) return null;
    const data: any = await resp.json();
    return data && data.msg ? String(data.msg) : null;
  } catch {
    return null;
  }
}

/**
 * Resolves a subaccount from (gas_wallet_api_key, subaccount_name) — the auth
 * pair used by the six bot-level endpoints. Replaces api.R's crashing
 * encrypt_gas_wallet_api_key() lookup (see file header).
 */
async function findSubaccount(gasWalletApiKey: string, subaccountName: string, columns: string) {
  const token = gasWalletApiKeyToken(gasWalletApiKey);
  return dbQuery(
    `SELECT ${columns} FROM cex_subaccounts
     WHERE encrypted_gas_wallet_api_key = ? AND subaccount_name = ?`,
    [token, subaccountName]
  );
}

/** MySQL tinyint(1) -> the 0/1 integer jsonlite produced for R's logical. */
function toBool01(v: unknown): number {
  return v ? 1 : 0;
}

/** R's as.character(<timestamp>) — NA became a JSON null. */
function tsToString(v: unknown): string | null {
  if (v === null || v === undefined) return null;
  if (v instanceof Date) {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${v.getFullYear()}-${p(v.getMonth() + 1)}-${p(v.getDate())} ${p(v.getHours())}:${p(v.getMinutes())}:${p(v.getSeconds())}`;
  }
  return String(v);
}

// ===========================================================================
// POST /registerCEXSubaccount
// ===========================================================================

/**
 * @openapi
 * /registerCEXSubaccount:
 *   post:
 *     summary: Register a CEX subaccount with encrypted credentials
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: gas_wallet_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: exchange
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: cex_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: cex_secret
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: cex_passphrase
 *         schema: { type: string }
 *       - in: query
 *         name: payment_network
 *         schema: { type: string, default: base }
 *       - in: query
 *         name: settings
 *         schema: { type: string }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Subaccount registered.
 */
router.post('/registerCEXSubaccount', async (req: Request, res: Response) => {
  // Gateway-layer sanitization, applied before anything else (as in R).
  const managerRaw = param(req, 'manager');
  const manager = managerRaw === undefined ? '' : managerRaw.toLowerCase();
  const gasWalletApiKey = param(req, 'gas_wallet_api_key');
  const exchange = sanitizeExchange(param(req, 'exchange') ?? '');
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const cexApiKey = param(req, 'cex_api_key') ?? '';
  const cexSecret = param(req, 'cex_secret') ?? '';
  const cexPassphrase = param(req, 'cex_passphrase') ?? '';
  const settings = param(req, 'settings') ?? '';
  const signature = param(req, 'signature');
  // The gateway shim never forwarded payment_network, so the 8002 default
  // ('base') always won in practice. Accepting it here is a superset that
  // leaves the previous effective behaviour unchanged for existing callers.
  const paymentNetworkRaw = param(req, 'payment_network') ?? 'base';

  // Gateway-layer required-param checks (gateway order: manager, key, sig).
  if (!manager) return res.json(fail(400, 'manager is required'));
  if (!gasWalletApiKey) return res.json(fail(400, 'gas_wallet_api_key is required'));
  if (!signature) return res.json(fail(400, 'signature is required'));

  try {
    // --- api.R order below, preserved exactly ---
    if (!isSignatureFormatValid(signature)) {
      return res.json(fail(401, 'Invalid Signature Format'));
    }
    if (!(await verifySignatureViaExpress(signature, manager))) {
      return res.json(fail(401, 'Invalid Signature'));
    }

    const validNetworks = ['ethereum', 'polygon', 'optimism', 'arbitrum', 'base'];
    const paymentNetwork = paymentNetworkRaw.toLowerCase();
    if (!validNetworks.includes(paymentNetwork)) {
      return res.json(fail(400, `Invalid payment_network. Must be one of: ${validNetworks.join(', ')}`));
    }

    if (!isValidAPIKey(gasWalletApiKey)) {
      return res.json(fail(400, 'Invalid gas wallet API key'));
    }

    const gasWallet = await getWalletForApiKey(gasWalletApiKey);
    if (!gasWallet) {
      return res.json(fail(400, 'Unable to retrieve gas wallet from API key'));
    }

    const encryptedGasKey = gasWalletApiKeyToken(gasWalletApiKey);

    // R's gas-balance minimum check is commented out upstream (getGasBalances
    // is broken there), so total_gas_usd is hard-coded 0 and no minimum is
    // enforced. Replicated as-is — re-enabling it here would be a behaviour
    // change, and is reported rather than made silently.
    const totalGasUsd = 0;

    const isCoinbaseCloud = exchange === 'coinbase' && /^organizations\/.*\/apiKeys\//.test(cexApiKey);

    const passphraseRequired =
      ['okx', 'kucoin', 'bitget'].includes(exchange) || (exchange === 'coinbase' && !isCoinbaseCloud);

    if (passphraseRequired && !cexPassphrase) {
      return res.json(
        fail(400, `${exchange} requires a passphrase (use legacy API keys or provide passphrase)`)
      );
    }

    if (isCoinbaseCloud && !/BEGIN EC PRIVATE KEY/.test(cexSecret)) {
      return res.json(fail(400, 'Invalid EC private key format. Must be PEM format with BEGIN/END markers'));
    }

    const encryptedApiKey = encryptCexCredential(cexApiKey);
    const encryptedSecret = encryptCexCredential(cexSecret);
    const encryptedPassphrase = cexPassphrase ? encryptCexCredential(cexPassphrase) : null;

    if (!encryptedApiKey || !encryptedSecret) {
      return res.json(fail(500, 'Failed to encrypt CEX credentials'));
    }

    const settingsJson = settings ? settings : null;

    const existing = await dbQuery(
      `SELECT id FROM cex_subaccounts
       WHERE manager_wallet = ? AND exchange = ? AND subaccount_name = ?`,
      [manager, exchange, subaccountName]
    );
    if (existing.length > 0) {
      return res.json(fail(400, `Subaccount '${subaccountName}' already exists on ${exchange}`));
    }

    await dbExecute(
      `INSERT INTO cex_subaccounts
        (manager_wallet, gas_wallet, encrypted_gas_wallet_api_key, payment_network, exchange,
         subaccount_name, cex_api_key_encrypted, cex_secret_encrypted, cex_passphrase_encrypted,
         settings, is_active, gas_balance_usd, last_gas_check)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE, ?, NOW())`,
      [
        manager,
        gasWallet.toLowerCase(),
        encryptedGasKey,
        paymentNetwork,
        exchange,
        subaccountName,
        encryptedApiKey,
        encryptedSecret,
        encryptedPassphrase,
        settingsJson,
        totalGasUsd.toFixed(2),
      ]
    );

    const idRows = await dbQuery(
      `SELECT id FROM cex_subaccounts WHERE manager_wallet = ? AND subaccount_name = ?`,
      [manager, subaccountName]
    );
    const subaccountId = idRows.length > 0 ? idRows[0].id : null;

    // Credentials are NEVER forwarded to Telegram — only non-secret metadata.
    notifyApiActivity({
      status: 'success',
      endpoint: 'registerCEXSubaccount',
      apiKey: gasWalletApiKey,
      fields: { manager, exchange, subaccount_name: subaccountName, payment_network: paymentNetwork },
      response: `subaccount_id: ${subaccountId}`,
    });

    return res.json({
      status: box('success'),
      status_code: box(200),
      message: box('CEX subaccount registered successfully'),
      subaccount_id: box(subaccountId),
      gas_balance_usd: box(totalGasUsd),
      payment_network: box(paymentNetwork),
    });
  } catch (e: any) {
    // Message must never echo credentials; only the DB/driver text is used.
    console.log(`Error: registerCEXSubaccount — manager: ${manager} exchange: ${exchange} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail',
      endpoint: 'registerCEXSubaccount',
      fields: { manager, exchange, subaccount_name: subaccountName },
      response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// POST /setCEXSide
// ===========================================================================

/**
 * @openapi
 * /setCEXSide:
 *   post:
 *     summary: Set trading side and parameters for a CEX bot
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: gas_wallet_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pair
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: side
 *         required: true
 *         schema: { type: string, enum: [long, neutral, hold] }
 *       - in: query
 *         name: max_usd
 *         required: true
 *         schema: { type: number }
 *       - in: query
 *         name: share
 *         required: true
 *         schema: { type: number }
 *       - in: query
 *         name: strategy
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Bot created or updated.
 */
router.post('/setCEXSide', async (req: Request, res: Response) => {
  const gasWalletApiKey = param(req, 'gas_wallet_api_key');
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const pair = sanitizePair(param(req, 'pair') ?? '');
  const side = (param(req, 'side') ?? '').toLowerCase();
  const maxUsdRaw = param(req, 'max_usd');
  const shareRaw = param(req, 'share');
  let strategy = param(req, 'strategy') ?? '';

  // R (plumber) 500'd on any missing required arg. Returning a 400 instead is
  // strictly safer and cannot break a caller that was receiving an error page.
  if (!gasWalletApiKey || !subaccountName || !pair || !side || maxUsdRaw === undefined || shareRaw === undefined) {
    return res.json(fail(400, 'Missing required parameters: gas_wallet_api_key, subaccount_name, pair, side, max_usd, share'));
  }

  const maxUsd = Number(maxUsdRaw);
  const share = Number(shareRaw);
  if (!Number.isFinite(maxUsd) || !Number.isFinite(share)) {
    return res.json(fail(400, 'max_usd and share must be numeric'));
  }

  try {
    const subaccount = await findSubaccount(gasWalletApiKey, subaccountName, 'id, exchange, is_active');
    if (subaccount.length === 0) return res.json(fail(404, 'Subaccount not found'));
    if (!subaccount[0].is_active) return res.json(fail(400, 'Subaccount is not active'));

    const subaccountId = subaccount[0].id;

    if (!strategy) strategy = 'custom';

    // NOTE (R behaviour preserved): setCEXSide silently falls back to a NULL
    // strategy_id when the named strategy does not exist, whereas
    // setCEXStrategy 404s for the same input. Asymmetric but not a crash, so
    // it is replicated rather than "fixed".
    let strategyId: number | null = null;
    if (strategy.toLowerCase() !== 'custom') {
      const sRows = await dbQuery(
        'SELECT id FROM cex_strategies WHERE strategy_name = ? AND is_active = TRUE',
        [strategy.toLowerCase()]
      );
      if (sRows.length > 0) strategyId = sRows[0].id;
    }

    const existing = await dbQuery(
      'SELECT id, side, previous_side FROM cex_bots WHERE subaccount_id = ? AND pair = ?',
      [subaccountId, pair]
    );

    if (existing.length > 0) {
      const botId = existing[0].id;
      const previousSide = existing[0].side;
      const sideChanged = previousSide !== side;

      // R spliced `last_side_change` unquoted so the column kept its old value
      // when the side did not change; both branches are reproduced here.
      await dbExecute(
        `UPDATE cex_bots
         SET side = ?, previous_side = ?, max_usd = ?, share = ?, strategy_id = ?,
             last_side_change = ${sideChanged ? 'NOW()' : 'last_side_change'}, updated_at = NOW()
         WHERE id = ?`,
        [side, previousSide, maxUsd.toFixed(2), share.toFixed(2), strategyId, botId]
      );

      // R used sprintf("Side changed: %s → %s") — the U+2192 arrow is kept.
      const message = sideChanged ? `Side changed: ${previousSide} → ${side}` : 'Bot updated';

      const payload = {
        status: box('success'),
        status_code: box(200),
        message: box(message),
        bot_id: box(botId),
        side: box(side),
        previous_side: box(previousSide),
        side_changed: box(sideChanged),
      };
      notifyApiActivity({
        status: 'success', endpoint: 'setCEXSide', apiKey: gasWalletApiKey,
        fields: { subaccount_name: subaccountName, pair, side, max_usd: maxUsd, share, strategy },
        response: message,
      });
      return res.json(payload);
    }

    await dbExecute(
      `INSERT INTO cex_bots (subaccount_id, strategy_id, pair, side, previous_side, max_usd, share, is_active)
       VALUES (?, ?, ?, ?, NULL, ?, ?, TRUE)`,
      [subaccountId, strategyId, pair, side, maxUsd.toFixed(2), share.toFixed(2)]
    );

    const idRows = await dbQuery('SELECT id FROM cex_bots WHERE subaccount_id = ? AND pair = ?', [
      subaccountId,
      pair,
    ]);
    const botId = idRows.length > 0 ? idRows[0].id : null;

    notifyApiActivity({
      status: 'success', endpoint: 'setCEXSide', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair, side, max_usd: maxUsd, share, strategy },
      response: 'Bot created',
    });

    return res.json({
      status: box('success'),
      status_code: box(200),
      message: box('Bot created'),
      bot_id: box(botId),
      side: box(side),
      previous_side: RNull, // R passed NULL -> jsonlite emits {}
      side_changed: box(true),
    });
  } catch (e: any) {
    console.log(`Error: setCEXSide — subaccount: ${subaccountName} pair: ${pair} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'setCEXSide', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair, side }, response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// GET /getCEXSide
// ===========================================================================

/**
 * @openapi
 * /getCEXSide:
 *   get:
 *     summary: Get trading side and parameters for CEX bot(s)
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: gas_wallet_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pair
 *         description: Optional. When omitted, all bots for the subaccount are returned.
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Bot details.
 */
router.get('/getCEXSide', async (req: Request, res: Response) => {
  const gasWalletApiKey = param(req, 'gas_wallet_api_key');
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const pairRaw = param(req, 'pair');
  const pair = pairRaw ? sanitizePair(pairRaw) : '';

  if (!gasWalletApiKey || !subaccountName) {
    return res.json(fail(400, 'Missing required parameters: gas_wallet_api_key, subaccount_name'));
  }

  try {
    const subaccount = await findSubaccount(gasWalletApiKey, subaccountName, 'id, exchange, subaccount_name');
    if (subaccount.length === 0) return res.json(fail(404, 'Subaccount not found'));

    const sub = subaccount[0];
    const subaccountId = sub.id;

    const selectBots = `SELECT b.id, b.pair, b.side, b.previous_side, b.max_usd, b.share,
              b.is_active, b.last_side_change, b.created_at, b.updated_at, s.strategy_name
       FROM cex_bots b
       LEFT JOIN cex_strategies s ON b.strategy_id = s.id
       WHERE b.subaccount_id = ?`;

    if (pair) {
      const rows = await dbQuery(`${selectBots} AND b.pair = ?`, [subaccountId, pair]);
      if (rows.length === 0) return res.json(fail(404, 'Bot not found for this pair'));

      const b = rows[0];
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('Bot details retrieved'),
        bot: {
          id: box(b.id),
          subaccount_name: box(sub.subaccount_name),
          exchange: box(sub.exchange),
          pair: box(b.pair),
          side: box(b.side),
          previous_side: b.previous_side === null || b.previous_side === undefined ? RNull : box(b.previous_side),
          max_usd: box(Number(b.max_usd)),
          share: box(Number(b.share)),
          strategy: box(b.strategy_name === null || b.strategy_name === undefined ? 'custom' : b.strategy_name),
          is_active: box(toBool01(b.is_active)),
          last_side_change: box(tsToString(b.last_side_change)),
          created_at: box(tsToString(b.created_at)),
          updated_at: box(tsToString(b.updated_at)),
        },
      });
    }

    const rows = await dbQuery(`${selectBots} ORDER BY b.created_at DESC`, [subaccountId]);

    if (rows.length === 0) {
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('No bots found for this subaccount'),
        bots: [], // R's list() -> []
      });
    }

    const bots = rows.map((b: any) => ({
      id: box(b.id),
      pair: box(b.pair),
      side: box(b.side),
      previous_side: b.previous_side === null || b.previous_side === undefined ? RNull : box(b.previous_side),
      max_usd: box(Number(b.max_usd)),
      share: box(Number(b.share)),
      strategy: box(b.strategy_name === null || b.strategy_name === undefined ? 'custom' : b.strategy_name),
      is_active: box(toBool01(b.is_active)),
      last_side_change: box(tsToString(b.last_side_change)),
      created_at: box(tsToString(b.created_at)),
      updated_at: box(tsToString(b.updated_at)),
    }));

    return res.json({
      status: box('success'),
      status_code: box(200),
      message: box(`Found ${rows.length} bot(s)`),
      subaccount_name: box(sub.subaccount_name),
      exchange: box(sub.exchange),
      bots,
    });
  } catch (e: any) {
    console.log(`Error: getCEXSide — subaccount: ${subaccountName} error: ${e.message}`);
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// POST /setCEXStrategy   (hidden endpoint — no @openapi block)
// ===========================================================================
router.post('/setCEXStrategy', async (req: Request, res: Response) => {
  const gasWalletApiKey = param(req, 'gas_wallet_api_key');
  const subaccountName = param(req, 'subaccount_name') ?? '';
  const pair = sanitizePair(param(req, 'pair') ?? '');
  // Gateway lowercased strategy on the wire, so api.R only ever saw lowercase.
  const strategy = (param(req, 'strategy') ?? '').toLowerCase();

  if (!gasWalletApiKey || !subaccountName || !pair || !strategy) {
    return res.json(fail(400, 'Missing required parameters: gas_wallet_api_key, subaccount_name, pair, strategy'));
  }

  try {
    // NOTE (R behaviour preserved): the setCEXStrategy gateway shim did NOT
    // strip subaccount_name (unlike every other CEX shim), so a name
    // containing e.g. "." was forwarded verbatim and simply failed to match.
    // Not sanitizing here keeps that lookup behaviour identical; SQL safety is
    // provided by parameterisation rather than by the missing filter.
    const subaccount = await findSubaccount(gasWalletApiKey, subaccountName, 'id');
    if (subaccount.length === 0) return res.json(fail(404, 'Subaccount not found'));

    const bot = await dbQuery('SELECT id FROM cex_bots WHERE subaccount_id = ? AND pair = ?', [
      subaccount[0].id,
      pair,
    ]);
    if (bot.length === 0) {
      return res.json(fail(404, 'Bot not found. Create bot first using /setCEXSide'));
    }

    let strategyId: number | null = null;
    if (strategy !== 'custom') {
      const sRows = await dbQuery(
        'SELECT id FROM cex_strategies WHERE strategy_name = ? AND is_active = TRUE',
        [strategy]
      );
      if (sRows.length === 0) return res.json(fail(404, `Strategy '${strategy}' not found`));
      strategyId = sRows[0].id;
    }

    await dbExecute('UPDATE cex_bots SET strategy_id = ?, updated_at = NOW() WHERE id = ?', [
      strategyId,
      bot[0].id,
    ]);

    notifyApiActivity({
      status: 'success', endpoint: 'setCEXStrategy', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair, strategy },
      response: `Strategy updated to '${strategy}'`,
    });

    return res.json({
      status: box('success'),
      status_code: box(200),
      message: box(`Strategy updated to '${strategy}'`),
      bot_id: box(bot[0].id),
      strategy: box(strategy),
    });
  } catch (e: any) {
    console.log(`Error: setCEXStrategy — subaccount: ${subaccountName} pair: ${pair} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'setCEXStrategy', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair, strategy }, response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// DELETE /deleteCEXBot
// ===========================================================================

/**
 * @openapi
 * /deleteCEXBot:
 *   delete:
 *     summary: Delete a CEX bot configuration
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: gas_wallet_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pair
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Bot deleted.
 */
router.delete('/deleteCEXBot', async (req: Request, res: Response) => {
  const gasWalletApiKey = param(req, 'gas_wallet_api_key') ?? '';
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const pair = sanitizePair(param(req, 'pair') ?? '');

  // This is the ONLY CEX shim that gated on isValidAPIKey at the gateway, and
  // it used the gateway's 400/"Invalid API Key" wording. Preserved verbatim.
  if (!isValidAPIKey(gasWalletApiKey)) {
    return res.json(fail(400, 'Invalid API Key'));
  }

  if (!subaccountName || !pair) {
    return res.json(fail(400, 'Missing required parameters: subaccount_name, pair'));
  }

  try {
    const subaccount = await findSubaccount(gasWalletApiKey, subaccountName, 'id');
    if (subaccount.length === 0) return res.json(fail(404, 'Subaccount not found'));

    const affected = await dbExecute('DELETE FROM cex_bots WHERE subaccount_id = ? AND pair = ?', [
      subaccount[0].id,
      pair,
    ]);

    if (affected > 0) {
      notifyApiActivity({
        status: 'success', endpoint: 'deleteCEXBot', apiKey: gasWalletApiKey,
        fields: { subaccount_name: subaccountName, pair }, response: 'Bot deleted successfully',
      });
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('Bot deleted successfully'),
      });
    }
    return res.json(fail(404, 'Bot not found'));
  } catch (e: any) {
    console.log(`Error: deleteCEXBot — subaccount: ${subaccountName} pair: ${pair} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'deleteCEXBot', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair }, response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// POST /deactivateCEXBot
// ===========================================================================

/**
 * @openapi
 * /deactivateCEXBot:
 *   post:
 *     summary: Deactivate a CEX bot without deleting it
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: gas_wallet_api_key
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: pair
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Bot deactivated.
 */
router.post('/deactivateCEXBot', async (req: Request, res: Response) => {
  const gasWalletApiKey = param(req, 'gas_wallet_api_key');
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const pair = sanitizePair(param(req, 'pair') ?? '');

  if (!gasWalletApiKey || !subaccountName || !pair) {
    return res.json(fail(400, 'Missing required parameters: gas_wallet_api_key, subaccount_name, pair'));
  }

  try {
    const subaccount = await findSubaccount(gasWalletApiKey, subaccountName, 'id');
    if (subaccount.length === 0) return res.json(fail(404, 'Subaccount not found'));

    // R checked db_execute()'s affected-row count. Because the statement also
    // sets `updated_at = NOW()`, a matching row is always modified, so
    // deactivating an ALREADY-inactive bot still reports success (verified
    // live). Only a genuinely missing bot yields 0 rows -> 404. Identical to R,
    // which issued the same UPDATE and applied the same >0 test.
    const affected = await dbExecute(
      'UPDATE cex_bots SET is_active = FALSE, updated_at = NOW() WHERE subaccount_id = ? AND pair = ?',
      [subaccount[0].id, pair]
    );

    if (affected > 0) {
      notifyApiActivity({
        status: 'success', endpoint: 'deactivateCEXBot', apiKey: gasWalletApiKey,
        fields: { subaccount_name: subaccountName, pair }, response: 'Bot deactivated successfully',
      });
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('Bot deactivated successfully'),
      });
    }
    return res.json(fail(404, 'Bot not found'));
  } catch (e: any) {
    console.log(`Error: deactivateCEXBot — subaccount: ${subaccountName} pair: ${pair} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'deactivateCEXBot', apiKey: gasWalletApiKey,
      fields: { subaccount_name: subaccountName, pair }, response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// DELETE /deleteCEXSubaccount
// ===========================================================================

/**
 * @openapi
 * /deleteCEXSubaccount:
 *   delete:
 *     summary: Delete a CEX subaccount (cascade-deletes all of its bots)
 *     tags: [CEX]
 *     parameters:
 *       - in: query
 *         name: manager
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: subaccount_name
 *         required: true
 *         schema: { type: string }
 *       - in: query
 *         name: signature
 *         required: true
 *         schema: { type: string }
 *     responses:
 *       200:
 *         description: Subaccount deleted.
 */
router.delete('/deleteCEXSubaccount', async (req: Request, res: Response) => {
  const managerRaw = param(req, 'manager');
  const manager = managerRaw === undefined ? '' : managerRaw.toLowerCase();
  const subaccountName = sanitizeSubaccountName(param(req, 'subaccount_name') ?? '');
  const signature = param(req, 'signature') ?? '';

  try {
    if (!isSignatureFormatValid(signature) || !(await verifySignatureViaExpress(signature, manager))) {
      return res.json(fail(401, 'Invalid Signature'));
    }

    // ON DELETE CASCADE on cex_bots.subaccount_id removes the bots.
    const affected = await dbExecute(
      'DELETE FROM cex_subaccounts WHERE manager_wallet = ? AND subaccount_name = ?',
      [manager, subaccountName]
    );

    if (affected > 0) {
      notifyApiActivity({
        status: 'success', endpoint: 'deleteCEXSubaccount',
        fields: { manager, subaccount_name: subaccountName },
        response: 'Subaccount deleted successfully (all bots removed)',
      });
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('Subaccount deleted successfully (all bots removed)'),
      });
    }
    return res.json(fail(404, 'Subaccount not found'));
  } catch (e: any) {
    console.log(`Error: deleteCEXSubaccount — manager: ${manager} subaccount: ${subaccountName} error: ${e.message}`);
    notifyApiActivity({
      status: 'fail', endpoint: 'deleteCEXSubaccount',
      fields: { manager, subaccount_name: subaccountName }, response: e.message,
    });
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

// ===========================================================================
// GET /getAllCEXSubaccounts   (hidden endpoint — no @openapi block)
// ===========================================================================
router.get('/getAllCEXSubaccounts', async (req: Request, res: Response) => {
  const managerRaw = param(req, 'manager');
  const manager = managerRaw === undefined ? '' : managerRaw.toLowerCase();
  const signature = param(req, 'signature') ?? '';

  try {
    if (!isSignatureFormatValid(signature) || !(await verifySignatureViaExpress(signature, manager))) {
      return res.json(fail(401, 'Invalid Signature'));
    }

    const subaccounts = await dbQuery(
      `SELECT id, subaccount_name, exchange, gas_wallet, payment_network, is_active,
              total_balance_usd, gas_balance_usd, last_gas_check, created_at, updated_at
       FROM cex_subaccounts
       WHERE manager_wallet = ?
       ORDER BY created_at DESC`,
      [manager]
    );

    if (subaccounts.length === 0) {
      return res.json({
        status: box('success'),
        status_code: box(200),
        message: box('No subaccounts found'),
        subaccounts: [],
      });
    }

    const result = [];
    for (const sub of subaccounts) {
      const counts = await dbQuery(
        `SELECT COUNT(*) as total_bots,
                SUM(CASE WHEN b.is_active = TRUE THEN 1 ELSE 0 END) as active_bots
         FROM cex_bots b
         JOIN cex_subaccounts s ON b.subaccount_id = s.id
         WHERE s.manager_wallet = ? AND s.subaccount_name = ?`,
        [manager, sub.subaccount_name]
      );

      // Live exchange call; degrades to {assets: [], total_usd: 0} on failure,
      // exactly as R's tryCatch did.
      const balance = await getCexBalanceDetails(sub.id);

      result.push({
        subaccount_name: box(sub.subaccount_name),
        exchange: box(sub.exchange),
        gas_wallet: box(sub.gas_wallet),
        payment_network: box(sub.payment_network),
        is_active: box(toBool01(sub.is_active)),
        total_balance_usd: box(balance.total_usd),
        gas_balance_usd: box(Number(sub.gas_balance_usd)),
        last_gas_check: box(tsToString(sub.last_gas_check)),
        total_bots: box(counts.length > 0 ? Number(counts[0].total_bots) : 0),
        active_bots: box(counts.length > 0 ? Number(counts[0].active_bots ?? 0) : 0),
        assets: balance.assets.map((a) => ({
          currency: box(a.currency),
          free: box(a.free),
          used: box(a.used),
          total: box(a.total),
          usd_value: box(a.usd_value),
          price: box(a.price),
        })),
        created_at: box(tsToString(sub.created_at)),
        updated_at: box(tsToString(sub.updated_at)),
      });
    }

    return res.json({
      status: box('success'),
      status_code: box(200),
      message: box(`Found ${subaccounts.length} subaccount(s)`),
      subaccounts: result,
    });
  } catch (e: any) {
    console.log(`Error: getAllCEXSubaccounts — manager: ${manager} error: ${e.message}`);
    return res.json(fail(500, `Error: ${e.message}`));
  }
});

export default router;
