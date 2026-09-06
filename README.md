# Infinite Trading Cloud

Cloud-based automated cryptocurrency trading system with DeFi vault management,
ML-based strategies, and multi-chain support (base, optimism, arbitrum, polygon,
ethereum).

This repository mirrors the production EC2 environment at `/home/ubuntu/`.

**Production EC2**: `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`

---

## 🏛 Architecture (current)

Public traffic terminates at **nginx**, which proxies to a single
**Express/TypeScript API on port 8000**.

```
Internet
   │
   ▼
nginx  (api.infinitetrading.io)
   │   • rate limiting (limit_req_zone: 30r/m per IP, burst 20)
   │   • query-string injection filters, CORS
   │   • endpoint allowlist: /etc/nginx/snippets/itp_endpoints.conf
   ▼
Express API :8000   ← the only API service
   │
   ├── MySQL (infinitetrading)
   ├── Redis (caching)
   └── RPCs / dHEDGE SDK / CEX APIs
```

### Historical note: the R API is gone

The system previously ran **two** R services that have now been fully migrated
to Express and shut down:

| Retired service | Port | What it was |
|---|---|---|
| `plumber-api` (`src/api/api.R`) | 8002 | Business logic |
| `api-gateway` (`src/api/gateway/gateway.R`) | 8003 | Validation/sanitization proxy in front of 8002 |

Traffic used to flow `nginx → gateway:8003 → plumber:8002`. Both layers were
ported endpoint-by-endpoint into Express with byte-for-byte response parity
(including R/jsonlite's array-boxing wire format and its numeric error codes),
each endpoint verified against the R original *before* nginx was cut over.

**If you find docs or code referencing ports 8002/8003, `pep`, `gateway.R` or
`plumber`, they are describing the retired architecture.**

R is still used heavily for **strategies, tradebots, collectors and ML models** —
just not for serving the API.

---

## 📁 Repository Structure

```
infinite-trading-cloud/
├── infinitetrading/              # R trading system (strategies, bots, ML)
│   ├── src/
│   │   ├── api/                  # retired API + still-live helpers/db layer
│   │   │   ├── helpers/          #   endpoints.R = endpoint registry
│   │   │   └── mySQL/            #   schema + migrations
│   │   ├── strategies/           # live strategy bots (one PM2 process each)
│   │   ├── tradebot/             # core trading loop (defi_thread.R, pools.R)
│   │   ├── exchanges/            # CEX integrations
│   │   ├── executor/             # trade execution
│   │   ├── indicators/           # TA indicators
│   │   ├── ml/ + models/         # ML models
│   │   └── db/                   # Python data collectors (candles, messages)
│   └── coins.csv                 # symbol→contract map, loaded by updateCoins.R
│
├── infinitetrading_api/
│   ├── express/                  # ★ THE API (TypeScript, port 8000)
│   │   ├── src/requests/         #   one file per endpoint group
│   │   ├── src/utils/            #   telegram, parseDapp, ERC20, tx-simulator…
│   │   ├── src/rateLimit.ts      #   app-level limiter (defense in depth)
│   │   ├── scripts/              #   smoke tests + logHealthMonitor
│   │   └── build/                #   compiled output PM2 actually runs
│   └── ecosystem.config.js       # PM2 process definitions
│
├── infinitetrading-sdk/          # JS SDK + auto-compounder jobs
├── backtests/                    # all backtests + their charts
├── scripts/                      # ops scripts (key rotation, vault creation)
├── deploy.sh                     # main deployment entrypoint
└── startup.sh                    # boot: redis + pm2
```

---

## 🚀 Deployment

```bash
# Standard path: commit + push + sync to EC2 + restart
./deploy.sh "fix: connection pool exhaustion" --restart-api
```

⚠️ **The Express service is NOT deployed by `git pull` on EC2.**
`/home/ubuntu/infinitetrading_api` is a *different* git repo, and the Express
sources there are manual copies. To ship Express changes:

```bash
scp -i ~/.ssh/macmini.pem <files> ubuntu@<ec2>:/home/ubuntu/infinitetrading_api/express/src/...
ssh … "cd /home/ubuntu/infinitetrading_api/express && npx tsc -p . && pm2 restart infinitetrading-api"
```

### Changing which endpoints are publicly routable

nginx's allowlist is **generated**, never hand-edited:

```bash
# on EC2
/home/ubuntu/infinitetrading/src/api/gateway/deploy.sh
sudo nginx -t && sudo systemctl reload nginx
```

It reads `src/api/helpers/endpoints.R`. Note that R's `hidden_endpoints` array
only hides endpoints from the docs page — they remain public and routable, so
any generator must include them.

---

## ✅ Testing

```bash
cd infinitetrading_api/express
BASE_URL=http://localhost:8000 npx ts-node scripts/endpoint-smoke-test.ts
```

Covers validation parity (error codes 1000/1001/1002/1004), read contracts,
authz rejection, and batch fee minting. Exits non-zero, so it can gate deploys.

## 📡 Monitoring

- **Telegram**: `src/utils/telegram.ts` — API activity notifications.
- **Log health sweep**: `scripts/logHealthMonitor.js` runs every 6h via cron,
  scans all PM2 logs for errors/crash loops and emails a report via Resend
  (silent when clean).

---

## 📚 Documentation

- **Start here:** `.github/AI_CONTEXT.md` — overview and critical warnings
- **Common tasks:** `.github/COMMON_TASKS.md`
- **Architecture:** `.github/ARCHITECTURE.md`
- **API development:** `.github/guides/API_DEVELOPMENT.md`
- **Deployment:** `.github/guides/DEPLOYMENT.md` / `DEPLOYMENT_WORKFLOW.md`
- **Troubleshooting:** `.github/guides/TROUBLESHOOTING.md`
- **Vault deployment:** `VAULT_DEPLOYMENT.md`
