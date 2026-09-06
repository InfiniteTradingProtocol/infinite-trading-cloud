/**
 * utils/cexCrypto.ts — Node port of R's
 * infinitetrading/src/exchanges/cex_encryption_compact.R (also duplicated at
 * src/api/helpers/cex_helpers.R), used by the CEX endpoints ported from
 * api.R (port 8002).
 *
 * WIRE-COMPATIBLE with the R implementation so rows written by either side
 * remain readable by the other (the R cex-tradebot pm2 process still decrypts
 * `cex_*_encrypted` columns with the R version):
 *
 *   key        = sha256(CEX_ENCRYPTION_KEY)[0..16]       (AES-128)
 *   iv         = 16 random bytes
 *   ciphertext = AES-128-CTR(plaintext, key, iv)
 *   stored     = hex(iv) || hex(ciphertext)
 *
 * R's `openssl::aes_ctr_encrypt` uses a full 128-bit counter seeded with the
 * IV, which is exactly Node's 'aes-128-ctr'. Verified round-trip against R.
 *
 * ---------------------------------------------------------------------------
 * *** CRASH-BUG FIX (flagged, not silently changed) ***
 *
 * api.R called `encrypt_gas_wallet_api_key(gas_wallet_api_key)` in SIX places
 * (registerCEXSubaccount, setCEXSide, getCEXSide, setCEXStrategy,
 * deleteCEXBot, deactivateCEXBot) but that function is DEFINED NOWHERE in the
 * repository or on the EC2 host. Every one of those endpoints therefore
 * returned, in live production:
 *
 *   {"status":["fail"],"status_code":[500],
 *    "message":["Error: could not find function \"encrypt_gas_wallet_api_key\""]}
 *
 * (reproduced directly against both port 8002 and port 8003 before this port;
 * the same error also appears in the gateway logs going back months). The
 * consequence is that the entire public CEX surface has been non-functional,
 * and `cex_subaccounts` / `cex_bots` are both EMPTY (0 rows), so there is no
 * stored data whose encoding we must remain bug-compatible with.
 *
 * Per the migration rules, a crash-bug is fixed rather than replicated. The
 * fix must satisfy the way the value is used: it is written to
 * `cex_subaccounts.encrypted_gas_wallet_api_key` on register and then compared
 * with `WHERE encrypted_gas_wallet_api_key = '<value>'` on every read. That
 * requires a DETERMINISTIC transform, so `encrypt_cex_credential` (random IV
 * per call) could never have worked here even if it had been the intended
 * target — the very first lookup would have missed.
 *
 * So this is a keyed, deterministic *lookup token*, not an encryption:
 *
 *   token = hex(HMAC-SHA256(CEX_ENCRYPTION_KEY, "gas_wallet_api_key:" || key))
 *
 * Properties: deterministic (equality lookups work), one-way (a DB leak does
 * not yield gas-wallet API keys, which is strictly better than the reversible
 * encryption the column name implies), keyed (an attacker with the DB but not
 * CEX_ENCRYPTION_KEY cannot brute-force UUID keys offline), and 64 hex chars
 * (fits varchar(256) and its 255-prefix index).
 */

import crypto from 'crypto';

function encryptionKey(): string {
  const k = process.env.CEX_ENCRYPTION_KEY;
  if (!k) throw new Error('CEX_ENCRYPTION_KEY not set');
  return k;
}

/** sha256(CEX_ENCRYPTION_KEY)[0..16] — R: `sha256(charToRaw(key_env))[1:16]`. */
function aesKey(): Buffer {
  return crypto.createHash('sha256').update(encryptionKey(), 'binary').digest().subarray(0, 16);
}

/**
 * Port of R's encrypt_cex_credential(). Returns null for empty input, matching
 * R's `if (is.null(plaintext) || plaintext == "") return(NULL)`.
 */
export function encryptCexCredential(plaintext: string | null | undefined): string | null {
  if (plaintext === null || plaintext === undefined || plaintext === '') return null;
  try {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv('aes-128-ctr', aesKey(), iv);
    const enc = Buffer.concat([cipher.update(Buffer.from(plaintext, 'utf8')), cipher.final()]);
    return iv.toString('hex') + enc.toString('hex');
  } catch (e: any) {
    // R printed the error and returned NULL rather than throwing.
    console.log(`Encryption error: ${e.message}`);
    return null;
  }
}

/** Port of R's decrypt_cex_credential(). */
export function decryptCexCredential(encryptedHex: string | null | undefined): string | null {
  if (encryptedHex === null || encryptedHex === undefined || encryptedHex === '') return null;
  try {
    const iv = Buffer.from(encryptedHex.substring(0, 32), 'hex');
    const data = Buffer.from(encryptedHex.substring(32), 'hex');
    const decipher = crypto.createDecipheriv('aes-128-ctr', aesKey(), iv);
    return Buffer.concat([decipher.update(data), decipher.final()]).toString('utf8');
  } catch (e: any) {
    console.log(`Decryption error: ${e.message}`);
    return null;
  }
}

/**
 * Deterministic lookup token for `cex_subaccounts.encrypted_gas_wallet_api_key`.
 * See the CRASH-BUG FIX note in the file header for why this replaces api.R's
 * undefined `encrypt_gas_wallet_api_key()`.
 */
export function gasWalletApiKeyToken(gasWalletApiKey: string): string {
  return crypto
    .createHmac('sha256', encryptionKey())
    .update(`gas_wallet_api_key:${gasWalletApiKey}`)
    .digest('hex');
}
