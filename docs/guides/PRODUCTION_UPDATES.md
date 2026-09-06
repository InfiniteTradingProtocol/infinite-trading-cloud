# Production Update Runbook

How to change the Infinite Trading API safely.

**This is live trading infrastructure moving real funds.** A bad deploy does not
show up as a failed test — it shows up as a strategy silently not trading, or
trading wrongly. Follow this document exactly. It exists so you never have to
reconstruct the procedure under pressure.

---

## 0. Facts you must know before touching anything

| Fact | Consequence if you don't know it |
|---|---|
| **EC2 does not `git pull`.** `/home/ubuntu/infinitetrading_api` is a *separate* repo; the Express files there are untracked copies deployed by `scp`. | You commit, see nothing change, and assume the code is wrong. |
| **PM2 runs `build/src/index.js`, not the TypeScript.** | You `scp` a `.ts` file, restart, and your change has no effect. You must run `npx tsc -p .`. |
| **nginx has its own rate limit (30r/m, burst 20).** | A burst of tests gets 503 HTML that looks exactly like a broken endpoint. |
| **`hidden_endpoints` in `endpoints.R` is cosmetic, not access control.** Those endpoints are public and callable; they are only hidden from the docs page. | You assume something is private and expose a real hole. |
| **The nginx allowlist is generated and cumulative.** | Regenerating from a partial list silently removes live endpoints. |

Host: `ssh -i ~/.ssh/macmini.pem ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com`

---

## 1. Change locally

Work in `infinitetrading_api/express/`.

```bash
npx tsc -p . --noEmit    # must be clean before you go further
```

If you touched routing, validation, or anything a strategy calls, add a case to
`scripts/endpoint-smoke-test.ts` in the same change. A behaviour with no test
is a behaviour that will regress.

---

## 2. Test on the shadow first

The shadow is a second copy of the service on port **8010**. It is deliberately
**not** in the nginx allowlist, so nothing on the internet — and no live
strategy — can reach it. It is started by hand, on demand; it is not a PM2
service, so don't look for it in `pm2 list`.

```bash
# deploy to shadow (same tree, different entrypoint)
scp -i ~/.ssh/macmini.pem src/<changed>.ts \
    ubuntu@<host>:/home/ubuntu/infinitetrading_api/express/src/

ssh -i ~/.ssh/macmini.pem ubuntu@<host> '
  cd /home/ubuntu/infinitetrading_api/express &&
  npx tsc -p . &&
  npm run shadow          # foreground on :8010; Ctrl-C when finished
'
```

Exercise your change against `localhost:8010` and confirm it behaves as
intended before it goes anywhere near port 8000.

> **Note on `scripts/parity-test.ts`:** it diffs the shadow against the **R
> gateway on :8003**, which has been shut down. It is retained for historical
> reference and will not run as-is. The current regression gate is
> `scripts/endpoint-smoke-test.ts` (step 4) — extend that instead.

---

## 3. Deploy to production

```bash
scp -i ~/.ssh/macmini.pem src/<changed>.ts \
    ubuntu@<host>:/home/ubuntu/infinitetrading_api/express/src/

ssh -i ~/.ssh/macmini.pem ubuntu@<host> '
  cd /home/ubuntu/infinitetrading_api/express &&
  npx tsc -p . &&                       # MUST succeed; PM2 runs the build output
  pm2 restart infinitetrading-api
'
```

`src/index.ts` is a shared edit surface. **Merge into it additively** (patch the
specific lines); never overwrite it wholesale, or you will drop someone else's
middleware.

---

## 4. Verify on the box, before trusting the internet

Testing through `api.infinitetrading.io` first is a trap: nginx rate limiting
and caching will confuse the result. Check `localhost:8000` first.

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@<host> '
  sleep 3
  pm2 logs infinitetrading-api --lines 40 --nostream | grep -i error
  curl -s localhost:8000/openapi.json | python3 -c "import json,sys;print(len(json.load(sys.stdin)[\"paths\"]),\"paths\")"
'
```

Then the full live suite from your machine:

```bash
npx tsx scripts/endpoint-smoke-test.ts   # must be N/N, no failures
```

It exits non-zero on failure, so it can gate automation.

---

## 5. Only if you added a NEW endpoint: nginx

New endpoints are **not** reachable from the internet until they are in the
allowlist. The snippet is generated:

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@<host> '
  # 1. add the endpoint name to the `endpoints` array in
  #    /home/ubuntu/infinitetrading/src/api/helpers/endpoints.R
  # 2. regenerate + reload
  sudo /home/ubuntu/infinitetrading/src/api/gateway/deploy.sh
  sudo nginx -t && sudo systemctl reload nginx
'
```

Rules:
- The list is **cumulative**. Never generate it from a subset.
- **Never** generate it from an OpenAPI spec — specs exclude `hidden_endpoints`,
  which are real, public, and in use. Doing so silently breaks them.
- `nginx -t` must pass *before* you reload. A reload with a bad config takes the
  whole API down.

The docs page reads `endpoints.R` at startup, so adding the endpoint there also
updates Swagger — there is no second list to maintain.

---

## 6. Persist the process state

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@<host> 'pm2 save'
```

Skipping this means your changes survive until the next reboot, and then the
old process layout comes back. This is the single easiest step to forget.

---

## 7. Rollback

Fast path — the previous build is still on the box:

```bash
ssh -i ~/.ssh/macmini.pem ubuntu@<host> '
  cd /home/ubuntu/infinitetrading_api/express &&
  git -C ~/infinite-trading-cloud show HEAD~1:path/to/file.ts > src/file.ts   # or re-scp the old file
  npx tsc -p . && pm2 restart infinitetrading-api
'
```

Then re-run the smoke suite to confirm you are actually back to a good state.
If nginx was changed, revert the snippet and `nginx -t && systemctl reload nginx`.

---

## Checklist

- [ ] `npx tsc -p . --noEmit` clean locally
- [ ] Test added for the new/changed behaviour
- [ ] Deployed to shadow (:8010) and exercised the change there
- [ ] `scp` + **`npx tsc -p .`** + `pm2 restart` on production
- [ ] `pm2 logs` shows no errors; `localhost:8000` responds
- [ ] Full smoke suite passes against `api.infinitetrading.io`
- [ ] nginx allowlist updated *(new endpoints only)*, `nginx -t` passed
- [ ] `pm2 save`
- [ ] Committed and pushed
