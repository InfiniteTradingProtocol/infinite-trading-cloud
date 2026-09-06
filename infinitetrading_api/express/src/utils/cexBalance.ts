/**
 * utils/cexBalance.ts — Node port of R's `get_cex_balance_details()`
 * (infinitetrading/src/api/helpers/cex_helpers.R ~line 119), used by the
 * ported GET /getAllCEXSubaccounts.
 *
 * R decrypted the stored CEX credentials and then drove CCXT through
 * reticulate. This keeps the same split: credential decryption happens here in
 * Node (utils/cexCrypto.ts, wire-compatible with R), and the exchange calls go
 * to scripts/cex_balance_details.py, which uses the very same Python CCXT
 * install R was using. See that script's header for the CCXT-level parity
 * notes.
 *
 * Also replicated from R:
 *  - only `is_active = TRUE` subaccounts are queried; otherwise the result is
 *    an empty asset list with total_usd 0;
 *  - after a successful computation the cached columns are refreshed
 *    (`total_balance_usd`, `last_balance_check`, `last_balance_update`);
 *  - every failure path degrades to {assets: [], total_usd: 0} instead of
 *    throwing, so one unreachable exchange cannot fail the whole endpoint.
 */

import path from 'path';
import { spawn } from 'child_process';
import { dbQuery, dbExecute } from '../db';
import { decryptCexCredential } from './cexCrypto';

export interface CexAsset {
  currency: string;
  free: number;
  used: number;
  total: number;
  usd_value: number;
  price: number;
}

export interface CexBalanceDetails {
  assets: CexAsset[];
  total_usd: number;
}

const EMPTY: CexBalanceDetails = { assets: [], total_usd: 0 };

// Resolved relative to this file so it works from both src/ (ts-node) and
// build/src/ (compiled) layouts.
const HELPER = path.resolve(__dirname, '..', '..', '..', 'scripts', 'cex_balance_details.py');
const PYTHON = process.env.CEX_PYTHON || 'python3';
const TIMEOUT_MS = Number(process.env.CEX_BALANCE_TIMEOUT_MS || 30000);

function runHelper(payload: unknown): Promise<CexBalanceDetails> {
  return new Promise((resolve) => {
    let child: ReturnType<typeof spawn>;
    try {
      child = spawn(PYTHON, [HELPER], { stdio: ['pipe', 'pipe', 'pipe'] });
    } catch {
      return resolve(EMPTY);
    }

    let out = '';
    let settled = false;
    const done = (v: CexBalanceDetails) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(v);
    };
    const timer = setTimeout(() => {
      try { child!.kill('SIGKILL'); } catch { /* already gone */ }
      done(EMPTY);
    }, TIMEOUT_MS);

    child.stdout?.on('data', (d) => { out += d.toString(); });
    // stderr is drained but never surfaced: it can contain exchange diagnostics.
    child.stderr?.on('data', () => { /* ignored */ });
    child.on('error', () => done(EMPTY));
    child.on('close', () => {
      try {
        const parsed = JSON.parse(out);
        done({
          assets: Array.isArray(parsed.assets) ? parsed.assets : [],
          total_usd: Number(parsed.total_usd) || 0,
        });
      } catch {
        done(EMPTY);
      }
    });

    try {
      child.stdin?.end(JSON.stringify(payload));
    } catch {
      done(EMPTY);
    }
  });
}

export async function getCexBalanceDetails(subaccountId: number): Promise<CexBalanceDetails> {
  try {
    const rows = await dbQuery(
      `SELECT exchange, cex_api_key_encrypted, cex_secret_encrypted, cex_passphrase_encrypted
       FROM cex_subaccounts WHERE id = ? AND is_active = TRUE`,
      [subaccountId]
    );
    if (rows.length === 0) return EMPTY;

    const row = rows[0];
    const apiKey = decryptCexCredential(row.cex_api_key_encrypted);
    const secret = decryptCexCredential(row.cex_secret_encrypted);
    const passphrase = row.cex_passphrase_encrypted
      ? decryptCexCredential(row.cex_passphrase_encrypted)
      : null;

    if (!apiKey || !secret) return EMPTY;

    const result = await runHelper({
      exchange: row.exchange,
      api_key: apiKey,
      secret,
      passphrase,
    });

    try {
      await dbExecute(
        `UPDATE cex_subaccounts
         SET total_balance_usd = ?, last_balance_check = NOW(), last_balance_update = NOW()
         WHERE id = ?`,
        [Number(result.total_usd.toFixed(2)), subaccountId]
      );
    } catch (e: any) {
      console.log(`getCexBalanceDetails — cache update failed for id ${subaccountId}: ${e.message}`);
    }

    return result;
  } catch (e: any) {
    console.log(`Error fetching CEX balance details for id ${subaccountId}: ${e.message}`);
    return EMPTY;
  }
}
