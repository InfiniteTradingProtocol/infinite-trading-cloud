# API Development

How to add or change an endpoint in the Express API.

To *deploy* the change, follow [`PRODUCTION_UPDATES.md`](PRODUCTION_UPDATES.md).
This document covers writing it.

---

## Local setup

```bash
cd infinitetrading_api/express
npm install
npx tsc -p . --noEmit     # typecheck without emitting
```

## Where code goes

```
src/
├── requests/          One file per endpoint or endpoint family
├── utils/             telegram, parseDapp, ERC20, RetryProvider, tx helpers
├── docs/              Swagger: setupDocs.ts, openapiComponents.ts,
│                      endpointVisibility.ts
├── basicCheck.ts      Shared validation (network / protocol / apiKey)
├── frontendKey.ts     Shared frontend API key
├── protocolAlias.ts   chamber -> dhedge normalization
├── rateLimit.ts       App-level rate limiting
├── index.ts           Route registration — SHARED, edit additively
├── db.ts              MySQL pool
├── rpc.ts             RPC providers
└── txFees.ts          Gas/fee calculation
```

---

## Adding an endpoint

### 1. Write the handler

Use a `Router`, and support both GET and POST unless there's a reason not to —
callers pass parameters either way, so handlers merge `req.query` and
`req.body`.

```ts
import { Router, Request, Response } from 'express';
import { basicCheck, toRWireFormat, isValidEthereumAddress } from '../basicCheck';

const router = Router();

async function handle(req: Request, res: Response) {
  const q: any = { ...req.query, ...req.body };

  const network  = String(q.network  || '').toLowerCase();
  const protocol = String(q.protocol || 'dhedge').toLowerCase();
  const apiKey   = String(q.apiKey   || '');

  // Always validate through basicCheck: it is the single choke point for
  // network/protocol/apiKey and keeps error codes consistent across the API.
  const check = await basicCheck({ network, protocol, apiKey });
  if (check.status === 'fail') return res.status(200).send(toRWireFormat(check));

  // ... endpoint logic
}

router.get('/myEndpoint', handle);
router.post('/myEndpoint', handle);
export default router;
```

### 2. Register it in `index.ts`

`index.ts` is edited by many changes at once. Add your two lines; do not
rewrite the file.

```ts
import myEndpointRouter from "./requests/myEndpoint"
app.use(myEndpointRouter)
```

### 3. Document it

Add an `@openapi` JSDoc block above the handler. Reuse the shared parameter
components so the Swagger UI renders dropdowns and defaults instead of
free-text boxes:

```ts
/**
 * @openapi
 * /myEndpoint:
 *   get:
 *     summary: One line, in plain language
 *     tags: [Trading]
 *     parameters:
 *       - $ref: '#/components/parameters/ApiKeyParam'
 *       - $ref: '#/components/parameters/NetworkParam'
 *       - $ref: '#/components/parameters/ProtocolParam'
 *       - $ref: '#/components/parameters/PoolParam'
 *     responses:
 *       200:
 *         description: What success looks like.
 */
```

Components live in `src/docs/openapiComponents.ts`. Add new shared ones there
rather than inlining an enum, or the lists drift.

### 4. Make it reachable

**A new endpoint is not reachable from the internet until it is in the nginx
allowlist**, even though it works on `localhost:8000`. Add its name to the
`endpoints` array in `infinitetrading/src/api/helpers/endpoints.R`, then
regenerate (see [`PRODUCTION_UPDATES.md`](PRODUCTION_UPDATES.md) §5).

The docs page reads the same file at startup, so this also publishes it to
Swagger — there is no second list.

To keep an endpoint callable but *hidden from the docs*, put it in
`hidden_endpoints` instead. **This is cosmetic only.** Hidden endpoints are
fully public and callable; hiding is not access control.

### 5. Add a test

Add a case to `scripts/endpoint-smoke-test.ts` covering the happy path and the
rejections. It runs against production and exits non-zero on failure.

```bash
npx tsx scripts/endpoint-smoke-test.ts
npx tsx scripts/endpoint-smoke-test.ts --only myEndpoint
```

---

## Conventions

**Validation.** Everything goes through `basicCheck()`. Address parameters get
`isValidEthereumAddress()`.

**Error shape.** Validation failures return HTTP 200 with a body whose fields
are 1-element arrays — a holdover from the original R/jsonlite wire format that
live strategies parse. Use `toRWireFormat()`; don't hand-roll it.

| Code | Meaning |
|---|---|
| 1000 | Unrecognized network |
| 1001 | Unrecognized protocol |
| 1002 | Invalid API key |
| 1004 | Invalid pool address |
| 1010 | Missing required parameter |

**Deprecated values must not error.** Live strategies still send retired
parameters. `platform=odos` is accepted and silently routed to `auto`;
`protocol=chamber` is normalized to `dhedge`. Rejecting these breaks running
strategies, so add an alias instead of a validation error.

**Auth schemes.** Most endpoints take a per-user UUID `apiKey`. A handful of
read-only ones (`getCandles`, `getTicks`, `getAllYields`, `getTotalYield`,
`getGasWalletPools`, `getAssociatedGasWallets`) use the shared frontend key —
check it with `isFrontendApiKey()` from `src/frontendKey.ts`, never a literal.

**Telegram.** `notifyTelegram()` never throws, by design: a monitoring channel
must not be able to fail a live trade. Don't add `await`-and-rethrow around it.

**Batching.** For multi-vault operations, batch through Multicall3
(`0xcA11bde05977b3631167028862bE2a173976CA11`, same address on every supported
network) so N vaults cost one transaction. See `mintAllFeesByManager.ts`.
