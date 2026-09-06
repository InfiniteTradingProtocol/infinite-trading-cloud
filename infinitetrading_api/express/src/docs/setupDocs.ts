/**
 * setupDocs.ts — mounts the public Swagger UI + OpenAPI spec for the API.
 *
 * Serves the same two paths nginx used to proxy to the retired R service, so
 * existing bookmarks and integrations keep working:
 *   GET /openapi.json
 *   GET /__docs__/
 *
 * The spec is built from `@openapi` JSDoc annotations on the route handlers,
 * then FILTERED so it advertises only endpoints that are genuinely reachable
 * from the internet and not deliberately hidden (see endpointVisibility.ts).
 * Building-then-filtering (rather than opting endpoints in) means a new
 * endpoint can never leak into the public docs just by existing.
 */

import swaggerJSDoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';
import { Express, Request, Response, NextFunction } from 'express';
import path from 'path';
import {
  filterPathsForPublicDocs,
  PUBLIC_ENDPOINTS,
  DOC_HIDDEN_ENDPOINTS,
} from './endpointVisibility';
import { openapiComponents } from './openapiComponents';

const swaggerDefinition = {
  openapi: '3.0.0',
  info: {
    title: 'Infinite Trading Protocol API',
    version: '1.0.0',
    description:
      'Deploy automated trading strategies in DeFi without managing Web3 ' +
      'infrastructure. Endpoints cover vault management, automated trading, ' +
      'DeFi protocol interactions (Aave, Compound, Fluid, dHEDGE) and CEX ' +
      'integration.\n\n' +
      'All endpoints require an API key. Networks: base, optimism, arbitrum, ' +
      'polygon, ethereum.',
  },
  servers: [{ url: 'https://api.infinitetrading.io', description: 'Production' }],
  components: openapiComponents,
};

const options: swaggerJSDoc.Options = {
  definition: swaggerDefinition,
  apis: [
    // Both .ts (ts-node/dev) and .js (compiled build/ that PM2 actually runs).
    path.join(__dirname, '../requests/*.ts'),
    path.join(__dirname, '../requests/*.js'),
  ],
};

const fullSpec = swaggerJSDoc(options) as { paths?: Record<string, unknown> };

const publicSpec = {
  ...fullSpec,
  paths: filterPathsForPublicDocs(fullSpec.paths || {}),
};

/**
 * The docs page is unauthenticated, matching the previous public behavior.
 * Kept as a named middleware so adding auth later is a one-line change here
 * instead of a scattered edit across routes.
 */
function docsGuard(_req: Request, _res: Response, next: NextFunction) {
  next();
}

export function setupDocs(app: Express): void {
  const documented = Object.keys(publicSpec.paths || {}).length;
  console.log(
    `[docs] serving ${documented} documented paths ` +
      `(${PUBLIC_ENDPOINTS.length} public endpoints, ` +
      `${DOC_HIDDEN_ENDPOINTS.length} intentionally hidden)`,
  );

  app.get('/openapi.json', docsGuard, (_req, res) => res.json(publicSpec));
  app.use('/__docs__', docsGuard, swaggerUi.serve, swaggerUi.setup(publicSpec));
}
