# AGENTS.md — Infinite Trading Cloud

Entry point for AI agents. Read this file first; it is designed to be enough
context for most tasks without opening anything else.

> **This is LIVE production trading infrastructure handling real funds.**
> Verify before you change. Never leave production broken.

---

## 1. The five facts that cause the most damage when unknown

1. **Express is NOT deployed by git.** `/home/ubuntu/infinitetrading_api` on
   EC2 is a *different* git repo, and the Express sources there are manual
   copies. `git pull` on EC2 does nothing for the API. Deploy = `scp` → `tsc`
   → `pm2 restart`. See §4.
2. **nginx's endpoint allowlist is generated, never hand-edited.** Editing
   `/etc/nginx/snippets/itp_endpoints.conf` by hand gets silently overwritten.
   Regenerate with `deploy.sh`. See §5.
3. **The compiled output is what runs.** PM2 executes `build/src/index.js`.
   Editing `src/*.ts` without running `npx tsc -p .` on EC2 changes nothing.
4. **`src/index.ts` is a shared edit surface.** Merge additively; never
   overwrite it wholesale.
5. **The database is local MySQL, not RDS.** RDS was sunset. `max_connections`
   is 200.

## 2. Architecture

```
Internet → nginx (api.infinitetrading.io) → Express API :8000
                                              ├── MySQL (local)
                                              ├── Redis (cache)
                                              └── RPCs / dHEDGE SDK / CEX APIs
```

Express on port **8000** is the only API service. R is used for strategies,
tradebots, collectors and ML models — **not** for serving the API.

nginx handles TLS, CORS, query-string injection filtering, IP rate limiting
(30r/m, burst 20), and an endpoint allowlist. Express additionally enforces
its own limiter (`src/rateLimit.ts`) as defense in depth.

**Production EC2:** `ec2-3-135-99-211.us-east-2.compute.amazonaws.com`

```bash
ssh -i ~/.ssh/macmini.pem -o StrictHostKeyChecking=no \
  ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
```

## 3. Where things live

| Path | What |
|---|---|
| `infinitetrading_api/express/src/requests/` | **Endpoint handlers** — one file per group |
| `infinitetrading_api/express/src/index.ts` | Route registration (shared surface) |
| `infinitetrading_api/express/src/utils/` | telegram, parseDapp, ERC20, tx-simulator |
| `infinitetrading_api/express/src/rateLimit.ts` | App-level rate limiting |
| `infinitetrading_api/express/scripts/` | Smoke tests, log health monitor |
| `infinitetrading/src/strategies/` | Live strategy bots (one PM2 process each) |
| `infinitetrading/src/tradebot/` | Core loop: `defi_thread.R`, `pools.R` |
| `infinitetrading/src/api/helpers/endpoints.R` | Endpoint registry driving nginx |
| `infinitetrading/src/api/mySQL/` | Schema + migrations |
| `infinitetrading/coins.csv` | symbol→contract map (`updateCoins.R` loads it) |
| `backtests/` | All backtests and charts |

## 4. Deploying

```bash
# Strategies / R code / repo-tracked files:
./deploy.sh "message" --restart-api
```

**Express (the API) — must be done manually:**

```bash
EC2=ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com
scp -i ~/.ssh/macmini.pem <file> $EC2:/home/ubuntu/infinitetrading_api/express/src/requests/
ssh -i ~/.ssh/macmini.pem $EC2 \
  "cd /home/ubuntu/infinitetrading_api/express && npx tsc -p . && pm2 restart infinitetrading-api"
```

Then verify it actually came back:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8000/getAllBots?...
pm2 list | grep infinitetrading-api
```

## 5. Changing which endpoints are public

1. Add the route in Express.
2. Add the name to `infinitetrading/src/api/helpers/endpoints.R`.
3. Regenerate nginx **on EC2**:

```bash
sudo cp /etc/nginx/snippets/itp_endpoints.conf /tmp/itp_endpoints.conf.bak
sudo HOME=/home/ubuntu bash /home/ubuntu/infinitetrading/src/api/gateway/deploy.sh
grep proxy_pass /etc/nginx/snippets/itp_endpoints.conf   # MUST say 8000
```

⚠️ Back up the snippet first, and check `proxy_pass` after. `nginx -t` only
validates syntax, so a config aimed at a dead port passes and then 502s every
request — this has caused a real outage.

⚠️ `sudo` resets `$HOME` and the generator resolves `endpoints.R` relative to
it, hence `HOME=/home/ubuntu`.

⚠️ The generator takes a **cumulative** list. Omitting an already-public
endpoint removes it from nginx and breaks it.

⚠️ Never generate the allowlist from an OpenAPI spec. Specs exclude
deliberately-hidden endpoints, which are still public and routable.
`endpoints.R` is the source of truth.

## 6. API conventions (match these exactly)

- **Error shape:** `{status:"fail", status_code:<code>, message:"..."}`
- **Codes:** `1000` invalid network · `1001` invalid protocol · `1002`
  malformed apiKey · `1004` invalid pool address · also `1007/1008/1010/1011`
- **Networks:** base, optimism, arbitrum, polygon, ethereum (alias mainnet),
  hyperliquid
- **DEX platform:** default is `auto`. `odos` is **deprecated but must never
  error** — accept it and silently route to `auto` (live strategies still send
  it). See `src/utils/parseDapp.ts` / `DEFAULT_PLATFORM`.
- **Protocol:** `dhedge` (default). `chamber` is the current brand name and is
  normalized to `dhedge` in middleware (`src/protocolAlias.ts`), so every
  endpoint accepts it.
- **Shared frontend key:** `FRONTEND_API_KEY` in `express/.env`. Check it with
  `isFrontendApiKey()` from `src/frontendKey.ts` — never a string literal.
- **Telegram:** call `notifyApiActivity()` from `src/utils/telegram.ts`. It
  never throws by design — a monitoring channel must not fail a live trade.

## 7. Testing

```bash
cd infinitetrading_api/express
BASE_URL=http://localhost:8000 npx ts-node scripts/endpoint-smoke-test.ts
```

Covers validation parity, read contracts, authz rejection, batch fee minting.
Exits non-zero, so it can gate a deploy. Run it on EC2 against
`localhost:8000` (bypasses nginx noise), then against
`https://api.infinitetrading.io` to confirm public routing.

**Safe test credentials** (dust-only, ~$0.0005 USDC — pipelines run fully and
fail safely at gas guards):
`apiKey=eddf4668-f5fc-4d20-8ce5-17f50722abdf`,
`pool=0x9b1a83432996e4e075dd24d4ed7288a2c4ca730a`, `network=optimism`.

## 8. Monitoring

- **Telegram** — API activity notifications.
- **Log health sweep** — `scripts/logHealthMonitor.js`, every 6h via cron;
  scans all PM2 logs for errors and crash loops, emails via Resend, silent
  when clean.

```bash
pm2 list
pm2 logs infinitetrading-api --lines 50 --nostream
```

## 9. Rules for changes here

1. **Verify before cutover.** Test on `localhost:8000` on EC2 first.
2. **Never move real funds** while testing. Use `dryRun`/`callStatic`
   simulation and the dust credentials above.
3. **Don't change auth semantics as a side effect** of another change. Report
   weaknesses instead of silently "fixing" them.
4. **Preserve response shapes.** Live strategies parse these; a changed field
   name breaks trading.
5. **Roll back immediately** if a cutover misbehaves.

## 10. Deeper guides

| File | When |
|---|---|
| `docs/guides/PRODUCTION_UPDATES.md` | **Changing production** — the runbook |
| `docs/guides/API_DEVELOPMENT.md` | Adding/changing endpoints |
| `docs/guides/TROUBLESHOOTING.md` | Errors in production, misleading symptoms |
| `docs/guides/VAULT_DEPLOYMENT.md` | Launching a new strategy vault |
| `docs/guides/EC2_SETUP.md` | First-time EC2 setup |
| `docs/reference/ARCHITECTURE.md` | Services, ports, storage, nginx |
| `docs/reference/API.md` | Conventions, auth, error codes |
| `docs/strategies/` | Individual strategy notes |
