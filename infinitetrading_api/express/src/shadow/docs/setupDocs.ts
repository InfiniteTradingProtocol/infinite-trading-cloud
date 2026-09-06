/**
 * setupDocs.ts — mounts a Swagger UI docs page on the shadow service,
 * built from `@openapi` JSDoc comments in the endpoint files, filtered to
 * match nginx's real public-reachability rules (see endpointVisibility.ts).
 *
 * Mirrors R gateway's own pattern: build the FULL spec first, then delete
 * paths that shouldn't be shown, and serve the result — replicated here as
 * `filterPathsForPublicDocs()` instead of R's `spec$paths[[path]] <- NULL`
 * loop in gateway.R's `pr$setApiSpec()` hook.
 *
 * NOTE: this only affects the shadow service's OWN docs page for local/dev
 * verification (the shadow service on :8010 is never exposed via nginx).
 * When endpoints are eventually promoted to the main Express app (:8000),
 * this same setup should be copied there and wired into nginx's /docs
 * route (mirroring how /__docs__/ is proxied today for R) — NOT done yet,
 * per the standing "don't touch production routing" instruction.
 */

import swaggerJSDoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';
import { Express, Request, Response, NextFunction } from 'express';
import path from 'path';
import { filterPathsForPublicDocs } from './endpointVisibility';

const swaggerDefinition = {
  openapi: '3.0.0',
  info: {
    title: 'Infinite Trading Protocol API (Express shadow)',
    version: '1.0.0',
    description:
      'Express port of the R/plumber API gateway. This spec is filtered to ' +
      'show only endpoints actually reachable through nginx today, matching ' +
      "the live api.infinitetrading.io routing — not R's internal endpoint " +
      'lists, which can disagree with real nginx routing (see endpointVisibility.ts).',
  },
};

const options: swaggerJSDoc.Options = {
  definition: swaggerDefinition,
  // Scan both the shadow ports and the main production request handlers, so
  // the same annotations can be reused once endpoints are promoted to :8000.
  apis: [
    path.join(__dirname, '../endpoints/*.ts'),
    path.join(__dirname, '../../requests/*.ts'),
  ],
};

const fullSpec = swaggerJSDoc(options) as { paths?: Record<string, unknown> };

const publicSpec = {
  ...fullSpec,
  paths: filterPathsForPublicDocs(fullSpec.paths || {}),
};

/**
 * Simple guard mirroring how R's /__docs__/ + /openapi.json are exposed
 * today: no auth on the docs page itself (matches current live behavior),
 * but kept as a named middleware so a future auth requirement is a one-line
 * change here rather than scattered across routes.
 */
function docsGuard(_req: Request, _res: Response, next: NextFunction) {
  next();
}

export function setupDocs(app: Express): void {
  app.get('/openapi.json', docsGuard, (_req, res) => res.json(publicSpec));
  app.use('/__docs__', docsGuard, swaggerUi.serve, swaggerUi.setup(publicSpec));
}
