import express from "express";
import adminRouter from "./requests/admin"
import investRouter from "./requests/invest"
import tradeRouter from "./requests/trade_test"
import lendingRouter from "./requests/lending"
const app = express()
const PORT = process.env.PORT || 8005

app.use(express.urlencoded({ extended: true }))
app.use(express.json())
app.use(adminRouter)
app.use(investRouter)
app.use(tradeRouter)
app.use(lendingRouter)
app.listen(PORT, () => {
  console.log(`⚡️[server]: Server is running on http://localhost:${PORT} ...`)
})
