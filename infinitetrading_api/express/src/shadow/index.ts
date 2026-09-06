/**
 * shadow/index.ts — standalone Express app for the R→Express migration.
 *
 * This runs on its OWN port (default 8010), separate from the main production
 * Express API (port 8000). It exists purely so newly-ported endpoints can be
 * built and parity-tested against the live R gateway (port 8003) WITHOUT any
 * risk to production traffic, which keeps flowing through nginx -> R gateway
 * (8003) unchanged until each endpoint is individually verified and promoted.
 *
 * MIGRATION LIFECYCLE for one endpoint:
 *   1. Port the R handler's logic into src/shadow/endpoints/<name>.ts (this dir).
 *   2. Mount it below and restart this shadow service (pm2 or `npm run shadow:watch`).
 *   3. Run scripts/parity-test.ts against BOTH this shadow port and the live R
 *      gateway for a range of real + edge-case inputs; fix any mismatches.
 *   4. Once parity holds, move the ported file into src/requests/ (main app,
 *      port 8000) and mount it in src/index.ts.
 *   5. Update /etc/nginx/snippets/itp_endpoints.conf so ONLY that one endpoint's
 *      location block points to 127.0.0.1:8000 instead of 127.0.0.1:8003.
 *   6. Reload nginx. Monitor. The R gateway keeps serving everything else
 *      unchanged — this step is a single, reversible config change per endpoint.
 *
 * Run with: PORT=8010 npx ts-node src/shadow/index.ts
 * (or `npm run shadow` once added to package.json scripts)
 */

require('dotenv').config({ path: '.env' });

import express from 'express';
import getSymbolRouter from './endpoints/getSymbol';
import getContractRouter from './endpoints/getContract';
import yieldsRouter from './endpoints/yields';
import getCandlesRouter from './endpoints/getCandles';

const app = express();
const PORT = Number(process.env.SHADOW_PORT || 8010);
const HOST = process.env.HOST || '127.0.0.1';

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// ── Mount migrated endpoints here, one at a time ──────────────────────────
app.use(getSymbolRouter);
app.use(getContractRouter);
app.use(yieldsRouter);
app.use(getCandlesRouter);

app.get('/shadow/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'shadow-migration',
    mounted: ['/getSymbol', '/getContract', '/getTotalYield', '/getEstimatedAnualYield', '/getAllYields', '/getCandles'],
  });
});

app.listen(PORT, HOST, () => {
  console.log(`[shadow] Migration Express service running on http://${HOST}:${PORT}`);
  console.log(`[shadow] Mounted endpoints: /getSymbol, /getContract, /getTotalYield, /getEstimatedAnualYield, /getAllYields, /getCandles`);
  console.log(`[shadow] This is a TEST service only — not wired into nginx/production traffic.`);
});
