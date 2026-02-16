require(httr)
require(jsonlite)

ds_price = function(pair,network,exchange,native=FALSE,pricechange=FALSE,liquidity=FALSE,print=FALSE) {
  url <- "https://api.dexscreener.com/latest/dex/pairs/"
  ep = NULL; c= NULL
  if (network == "optimism") { ep = "optimism/" }
  else if (network == "polygon") { ep = "polygon/" }
  else if (network == "base") { ep = "base/" }
  if (exchange == "velodromeV2") {
        if (pair == "ITP-USDC") { c = "0xb84c932059a49e82c2c1bb96e29d59ec921998be" }
        else if (pair == "ITP-wstETH") { c = "0xdad7b4c48b5b0be1159c674226be19038814ebf6" }
        else if (pair == "ITP-WBTC")  { c = "0x93e40c357c4dc57b5d2b9198a94da2bd1c2e89ca" }
        else if (pair == "ITP-DHT") { c = "0x3d5cbc66c366a51975918a132b1809c34d5c6fa2" }
        else if (pair == "ITP-xOpenX") { c = "0x44fb5dc428c65576d5fce5298cf1c77ea28cf2dc" }
        else if (pair == "ITP-VELO") { c = "0xc04754f8027abbfe9eea492c9cc78b66946a07d1" }
        else if (pair == "ITP-OP") { c = "0x79f1af622fe2c636a2d946f03a62d1dfc8ca6de4" }
        else if (pair == "ITP-MAI") { c = "0x1ec3d6b917fbb4bf8536b683fb054b0ab1ff587a" }
        else if (pair == "alETH-WETH") { c = "0xa1055762336f92b4b8d2edc032a0ce45ead6280a" }
        else if (pair == "opxVELO-VELO") { c= "0xa80ad5c1f8c21b34b427ea432530ae7ff36e3926" }
        else if (pair == "frxETH-WETH") { c = "0x3f42dc59dc4df5cd607163bc620168f7ff7ab970" }
        else if (pair == "alUSD-USDC") { c = "0x4d7959d17b9710be87e3657e69d946914221bb88" }
        else if (pair == "sUSD-USDC") { c = "0x252cbdff917169775be2b552ec9f6781af95e7f6" }
        else if (pair == "MTA-USDC") { c = "0x8453cc52f2108ff9d1636b6a108db06ac137b72f" }
        else if (pair == "LUSD-USDC") { c = "0xf04458f7b21265b80fc340de7ee598e24485c5bb" }
        else if (pair == "tBTC-WBTC") { c = "0xe612cb2b5644aef0ad3e922bae70a8374c63515f" }
        ep = paste0(ep,c)
  }
  else if (exchange == "uniswapV3") {
        if (network == "polygon") {
                if (pair == "stMATIC-MaticX") ep = paste0(ep,"0xc63123aec88f6965d2792e96f9e8a3324dbbc6b0")
        }
        else if (network == "base") {
                if (pair == "cbEGGS-cbETH") { ep = paste0(ep,"0x89129db57374fdad1e79a3c081d83f670d011925") }
                else if (pair == "cbETH-WETH") { ep = paste0(ep,"0x47ca96ea59c13f72745928887f84c9f52c3d7348") }
        }
  }
  url = paste0(url,ep)
  response <- GET(url)
  if (print) print(paste0("querying: ",url))
  if (response$status_code == 200) {
    # Parse JSON response
    data <- fromJSON(content(response, "text"))
    if (print) print(data)
    # Extract priceUsd value
    if (pricechange) {
            pricechange = c(as.numeric(data$pair$priceChange$m5),as.numeric(data$pair$priceChange$h1),as.numeric(data$pair$priceChange$h6),as.numeric(data$pair$priceChange$h24))
            if (!native) { pricechange = c(as.numeric(data$pairs$priceUsd),pricechange) }
            else {pricechange = c(as.numeric(data$pairs$priceNative),pricechange) }
            if (print) print(pricechange)
            return(pricechange)
    }
    else if (liquidity) {
            data$pair$liquidity$price = as.numeric(data$pairs$priceUsd)
            return(data$pair$liquidity)
    }
    else if (!native) { return(as.numeric(data$pairs$priceUsd)) }
    else { return(as.numeric(data$pairs$priceNative)) }
  } else {
    cat("Error:", http_status(response)$reason, "\n")
    return(NULL)
 }
}

lp_fee = 0.01
cbEGGS_cbETH_price = ds_price("cbEGGS-cbETH","base","uniswapV3",native=TRUE)
cbETH_WETH_price = ds_price("cbETH-WETH","base","uniswapV3",native=TRUE)
cbETH_WETH_price = cbETH_WETH_price*cbEGGS_cbETH_price
print(paste0("cbETH-ETH price:", cbETH_WETH_price))
print(paste0("LP Fee: ",lp_fee*100,"%"))
print(paste0("cbETH-ETH price with fee (no price impact):", cbETH_WETH_price*(1 + lp_fee) ))

