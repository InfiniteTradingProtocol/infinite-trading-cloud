# Architecture

## Request path

```
Internet
  │
  ▼
nginx  (api.infinitetrading.io)
  │   TLS, CORS, query-string injection filtering,
  │   IP rate limiting (30r/m, burst 20), endpoint allowlist
  ▼
Express API  :8000        ← the only API service
  │
  ├── MySQL (local, on the same EC2 box)
  ├── Redis (vault guards, quotes, DEX bans, tick cache)
  └── RPC providers → dHEDGE SDK → chain
```

Express serves the entire public API. R is used for trading strategies,
tradebots, collectors and ML models — it does not serve HTTP.

**Production host:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`

```bash
ssh -i ~/.ssh/macmini.pem -o StrictHostKeyChecking=no \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

## Two repositories, one machine

This is the single most common source of confusion.

| Location | Git? | Deployed by |
|---|---|---|
| `~/infinite-trading-cloud` (your machine) | yes, this repo | — |
| `/home/ubuntu/infinitetrading` (EC2) | separate repo | git |
| `/home/ubuntu/infinitetrading_api` (EC2) | separate repo; Express files are untracked copies | **`scp`** |

`git pull` on EC2 does not update the API. Deploy is `scp` → `npx tsc -p .` →
`pm2 restart`. PM2 runs `build/src/index.js`, so skipping the TypeScript build
means nothing changes.

## Processes

All services run under PM2 (not screen). ~21 processes:

| Process | Role |
|---|---|
| `infinitetrading-api` | The Express API (port 8000) |
| `tradebot` | Core DeFi trading loop |
| `cex-tradebot` | Centralized-exchange trading |
| `strategy-*` | One process per live strategy |
| `candles-collector`, `messages-collector` | Market/message ingestion |
| `gas-monitor`, `pools-monitor`, `prices-monitor`, `yields-monitor` | Monitoring |
| `ml-models` | Model scoring |

```bash
pm2 list
pm2 logs infinitetrading-api --lines 50 --nostream
pm2 save        # persist after start/stop/delete, or a reboot undoes it
```

## Storage

**MySQL** — local to the EC2 instance, `max_connections = 200`. (RDS was sunset;
pool sizing based on the old 30-connection limit under-provisions by ~7x.)

```bash
mysql -u richard_clare -p infinitetrading
```

Key tables: `gas_wallets` (known vaults, gas wallet links), `api_tokens`,
`dhedge_sides` (strategy positions), `coins` (unique on `(contract,
network_id)` — OP-Stack chains share predeploy addresses, so `contract` alone
is not unique), `networks`, `protocols`, `cex_*`.

**Redis** — vault guard whitelists (24h TTL), quotes, DEX ban state, ticks.

## Networks

`base`, `optimism`, `arbitrum`, `polygon`, `ethereum` (alias `mainnet`),
`hyperliquid`.

Multicall3 is at `0xcA11bde05977b3631167028862bE2a173976CA11` on all of them,
which is what makes cross-vault batching possible.

## nginx

Config lives in `/etc/nginx/sites-available/`; the endpoint allowlist is the
generated snippet `/etc/nginx/snippets/itp_endpoints.conf`.

**The allowlist is generated, never hand-edited** — edits are silently
overwritten on the next regeneration. It is produced from the `endpoints` and
`hidden_endpoints` arrays in
`infinitetrading/src/api/helpers/endpoints.R` by
`infinitetrading/src/api/gateway/deploy.sh`.

Two properties matter:

- The list is **cumulative**. An endpoint missing from it 404s publicly while
  still working on `localhost:8000`.
- `hidden_endpoints` only hides an endpoint from the docs page. Those endpoints
  remain fully public and callable. **It is not access control.**

## Rate limiting

Two independent layers:

| Layer | Limit | Notes |
|---|---|---|
| nginx | 30r/m, burst 20 | Returns 503 HTML. Bursty test suites trip this and the failure looks like a broken endpoint. |
| Express (`src/rateLimit.ts`) | 600/min default; 10/min on `llmIntrospect` | IPv6 keyed by /64 so a client cannot rotate addresses to evade it. |

## Documentation endpoints

`/openapi.json` and `/__docs__/` are served by Express (`src/docs/setupDocs.ts`).
The visibility list is parsed from `endpoints.R` at startup rather than
duplicated, so the docs cannot drift from the allowlist.
