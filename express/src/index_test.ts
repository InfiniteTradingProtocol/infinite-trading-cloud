import express from "express"
import tradeRouter from "./requests/trade_fixed"
const app = express()
const PORT = 8001

app.use(express.urlencoded({ extended: true }))
app.use(express.json())
app.use(tradeRouter)

app.listen(PORT, () => {
  console.log(`⚡️[TEST SERVER]: Running on http://localhost:${PORT}`)
  console.log(`Test endpoints:`)
  console.log(`  - GET  http://localhost:${PORT}/trade`)
  console.log(`  - POST http://localhost:${PORT}/approve`)
  console.log(`  - GET  http://localhost:${PORT}/checkAllowance`)
})
