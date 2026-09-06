import express from "express"
import adminRouter from "./requests/admin"
import investRouter from "./requests/invest"
import tradeRouter from "./requests/trade"
import tradeDexRouter from "./requests/trade-dex"
import lendingRouter from "./requests/lending"
import pricingRouter from "./requests/pricing"
import cexRouter from "./requests/cex"
import liquidityRouter from "./requests/liquidity"
import yieldsRouter from "./requests/yields"
import getTicksRouter from "./requests/getTicks"
import gasBalanceRouter from "./requests/gasBalance"
import getAssociatedGasWalletsRouter from "./requests/getAssociatedGasWallets"
import getGasWalletPoolsRouter from "./requests/getGasWalletPools"
import getAllBotsRouter from "./requests/getAllBots"
import getSymbolRouter from "./requests/getSymbol"
import getContractRouter from "./requests/getContract"
import getCandlesRouter from "./requests/getCandles"
import deleteBotRouter from "./requests/deleteBot"
import associateGasWalletRouter from "./requests/associateGasWallet"
import deassociateGasWalletRouter from "./requests/deassociateGasWallet"
import linkGasWalletRouter from "./requests/linkGasWallet"
import unlinkGasWalletRouter from "./requests/unlinkGasWallet"
import vaultTradeRouter from "./requests/vaultTrade"
import setBotRouter from "./requests/setBot"
import poolCompositionEnrichedRouter from "./requests/poolCompositionEnriched"
import mintManagerFeeBatchRouter from "./requests/mintManagerFeeBatch"
import mintAllFeesByManagerRouter from "./requests/mintAllFeesByManager"
import lendRouter from "./requests/lend"
import unlendRouter from "./requests/unlend"
import borrowRouter from "./requests/borrow"
import repayRouter from "./requests/repay"
import getHealthFactorRouter from "./requests/getHealthFactor"
import getPoolAaveDataRouter from "./requests/getPoolAaveData"
import aaveV3Router from "./requests/aaveV3"
import compoundV3Router from "./requests/compoundV3"
import fluidRouter from "./requests/fluid"
import approveRouter from "./requests/approve"
import addLiquidityPublicRouter from "./requests/addLiquidity"
import removeLiquidityPublicRouter from "./requests/removeLiquidity"
import mintManagerFeeRouter from "./requests/mintManagerFee"
import createGasWalletRouter from "./requests/createGasWallet"
import getNewApiKeyRouter from "./requests/getNewApiKey"
import cexPublicRouter from "./requests/cexPublic"
import llmIntrospectRouter from "./requests/llmIntrospect"
import { logger, requestLogger } from "./logger"
import { defaultRateLimiter, llmIntrospectRateLimiter } from "./rateLimit"
import { setupDocs } from "./docs/setupDocs"
import { protocolAliasMiddleware } from "./protocolAlias"

const app = express()
const PORT = Number(process.env.PORT || 8000)
const HOST = process.env.HOST || "127.0.0.1"

// Trust nginx as the only hop in front of this app so req.ip / X-Real-IP
// reflect the real client, matching R gateway's rate limiter (see rateLimit.ts).
app.set('trust proxy', 'loopback')

app.use(express.urlencoded({ extended: true }))
app.use(express.json())

// Rate limiting — mirrors R gateway.R's rate_limit_middleware (600 req/min per
// IP by default, 10 req/min for llmIntrospect). Defense-in-depth alongside
// nginx's limit_req_zone.
// Accept `protocol=chamber` (the dHEDGE rebrand) everywhere by rewriting it
// to the canonical `dhedge` before any router sees it.
app.use(protocolAliasMiddleware)

app.use('/llmIntrospect', llmIntrospectRateLimiter)
app.use(defaultRateLimiter)

// Add request logging middleware (disabled for cleaner logs)
// app.use(requestLogger)

// Public API docs: GET /openapi.json and /__docs__/ — the same paths nginx
// previously proxied to the retired R service, so existing links keep working.
setupDocs(app)

app.use(adminRouter)
app.use(investRouter)
app.use(tradeRouter)
app.use(tradeDexRouter)
app.use(lendingRouter)
app.use('/api/pricing', pricingRouter)
app.use(cexRouter)
app.use(liquidityRouter)
app.use(yieldsRouter)
app.use(getTicksRouter)
app.use(gasBalanceRouter)
app.use(getAssociatedGasWalletsRouter)
app.use(getGasWalletPoolsRouter)
app.use(getAllBotsRouter)
app.use(getSymbolRouter)
app.use(getContractRouter)
app.use(getCandlesRouter)
app.use(deleteBotRouter)
app.use(associateGasWalletRouter)
app.use(deassociateGasWalletRouter)
app.use(linkGasWalletRouter)
app.use(unlinkGasWalletRouter)
app.use(vaultTradeRouter)
app.use(setBotRouter)
app.use(poolCompositionEnrichedRouter)
app.use(mintManagerFeeBatchRouter)
app.use(mintAllFeesByManagerRouter)
app.use(lendRouter)
app.use(unlendRouter)
app.use(borrowRouter)
app.use(repayRouter)
app.use(getHealthFactorRouter)
app.use(getPoolAaveDataRouter)
app.use(aaveV3Router)
app.use(compoundV3Router)
app.use(fluidRouter)
app.use(approveRouter)
app.use(addLiquidityPublicRouter)
app.use(removeLiquidityPublicRouter)
app.use(mintManagerFeeRouter)
app.use(createGasWalletRouter)
app.use(getNewApiKeyRouter)
// Public CEX endpoints (setCEXSide, getCEXSide, setCEXStrategy, deleteCEXBot,
// deactivateCEXBot, registerCEXSubaccount, deleteCEXSubaccount,
// getAllCEXSubaccounts). Distinct from cexRouter above, which serves the
// internal /api/cex/* fee routes.
app.use(cexPublicRouter)
// Sits behind llmIntrospectRateLimiter, registered above (10 req/60s per IP).
app.use(llmIntrospectRouter)

app.listen(PORT, HOST, () => {
  logger.info(`⚡️[server]: Server is running on http://${HOST}:${PORT}`)
  logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`)
  logger.info(`Logging to: logs/api-*.log`)
})

// Graceful shutdown
process.on('SIGINT', () => {
  logger.info('SIGINT signal received: closing HTTP server')
  process.exit(0)
})

process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server')
  process.exit(0)
})

// Unhandled errors
process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception:', error)
  process.exit(1)
})

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason)
})
