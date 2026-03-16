// Initialize ODOS rate limiter FIRST (before any SDK imports)
import "./odosRateLimiter";

import express from "express"
import adminRouter from "./requests/admin"
import investRouter from "./requests/invest"
import tradeRouter from "./requests/trade"
import tradeOdosV2Router from "./requests/trade-odosv2"
import lendingRouter from "./requests/lending"
import pricingRouter from "./requests/pricing"
import { logger, requestLogger } from "./logger"

const app = express()
const PORT = process.env.PORT || 8000

app.use(express.urlencoded({ extended: true }))
app.use(express.json())

// Add request logging middleware (disabled for cleaner logs)
// app.use(requestLogger)

app.use(adminRouter)
app.use(investRouter)
app.use(tradeRouter)
app.use(tradeOdosV2Router)
app.use(lendingRouter)
app.use('/api/pricing', pricingRouter)

app.listen(PORT, () => {
  logger.info(`⚡️[server]: Server is running on http://localhost:${PORT}`)
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
