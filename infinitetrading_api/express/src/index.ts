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
import { logger, requestLogger } from "./logger"
import { defaultRateLimiter, llmIntrospectRateLimiter } from "./rateLimit"

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
app.use('/llmIntrospect', llmIntrospectRateLimiter)
app.use(defaultRateLimiter)

// Add request logging middleware (disabled for cleaner logs)
// app.use(requestLogger)

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
