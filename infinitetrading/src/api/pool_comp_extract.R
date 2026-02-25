# Extracted pool_comp function from defi.R
# Requires: jsonlite, httr

dhedge_pool_comp <- function(pool,network="polygon",apiKey=NULL,provider="alchemy",providerKey=NULL) {
  if (is.null(providerKey)) {
    providerKey <- Sys.getenv("ALCHEMY_BALANCES_APIKEY")
  }
  
  dhedge_ep <- "http://localhost:8000/"
  
  if (provider == "alchemy") {
    if (network == "polygon") { chain <- "polygon-mainnet" }
    else if (network == "optimism") { chain <- "opt-mainnet" }
    else if (network == "base") { chain <- "base-mainnet" }
    else if (network == "arbitrum") { chain <- "arb-mainnet" }
    else if (network == "ethereum") { chain <- "eth-mainnet" }
    else { stop("Unsupported network") }
    
    url <- paste0("https://", chain, ".g.alchemy.com/v2/", providerKey)
    
    tryCatch({
      res <- httr::POST(
        url,
        body = jsonlite::toJSON(list(
          jsonrpc = "2.0",
          id = 1,
          method = "alchemy_getTokenBalances",
          params = list(pool, "erc20")
        ), auto_unbox = TRUE),
        httr::content_type_json()
      )
      
      content <- httr::content(res, "parsed")
      if (!is.null(content$result$tokenBalances)) {
        balances <- content$result$tokenBalances
        return(balances)
      }
      return(list())
    }, error = function(e) {
      cat("Error fetching pool composition:", e$message, "\n")
      return(list())
    })
  } else {
    # Fallback to local endpoint
    url <- paste0(dhedge_ep, "poolComposition?pool=", pool, "&network=", network, "&apiKey=", apiKey)
    tryCatch({
      res <- httr::GET(url)
      return(httr::content(res, "parsed"))
    }, error = function(e) {
      cat("Error fetching pool composition from local endpoint:", e$message, "\n")
      return(list())
    })
  }
}

pool_comp <- function(pool, network, protocol = "dhedge", db = FALSE, apiKey=NULL, provider="alchemy", providerKey=NULL) {
  if (is.null(providerKey)) {
    providerKey <- Sys.getenv("ALCHEMY_BALANCES_APIKEY")
  }
  
  if (protocol == "dhedge") {
    return(dhedge_pool_comp(pool, network, apiKey, provider, providerKey))
  } else {
    stop("Unsupported protocol: ", protocol)
  }
}

cat("✅ pool_comp functions loaded\n")
get_usd_price = function(asset,composition) {
        asset_row = c(); asset_price = 0
        if (!is.null(composition)) { asset_row = which(composition[,4] == asset); }
        if (length(asset_row) > 0) { asset_price = as.numeric(composition[asset_row,6]); }
        asset_price = as.numeric(asset_price)
	if (asset_price > 0) { return(asset_price) }
	else { asset_price = 0 }
	return(asset_price)
}
is_btc = function(symbol) {
        symbol = toupper(symbol)
        return (is_btc_bull(symbol) || symbol == "WBTC" || symbol == "TBTC")
} 
is_eth = function(symbol) {
        symbol = toupper(symbol)
        return (is_eth_bull(symbol) || symbol == "WETH" || symbol == "FRXETH" || symbol == "ALETH" || symbol == "RETH" || symbol == "WSTETH" || symbol == "WEETH")
} 
is_btc_bull = function(asset) return((asset %in% c("BTCBULL3X","BTCBULL2X","BTCBULL4X")))
is_eth_bull = function(asset) return((asset %in% c("ETHBULL3X","ETHBULL2X")))
is_bull = function(asset) return((is_btc_bull(asset) || is_eth_bull(asset)))
is_bear = function(asset) return((asset %in% c("ETHBEAR1X","BTCBEAR1X")))
is_toros = function(asset) return((is_bull(asset) || is_bear(asset)))

is_eth = function(symbol) {
        symbol = toupper(symbol)
        return (is_eth_bull(symbol) || symbol == "WETH" || symbol == "FRXETH" || symbol == "ALETH" || symbol == "RETH" || symbol == "WSTETH" || symbol == "WEETH")
} 
is_eth_bull = function(asset) return((asset %in% c("ETHBULL3X","ETHBULL2X")))
is_bull = function(asset) return((is_btc_bull(asset) || is_eth_bull(asset)))
is_bear = function(asset) return((asset %in% c("ETHBEAR1X","BTCBEAR1X")))
is_toros = function(asset) return((is_bull(asset) || is_bear(asset)))

is_eth = function(symbol) {
        symbol = toupper(symbol)
        return (is_eth_bull(symbol) || symbol == "WETH" || symbol == "FRXETH" || symbol == "ALETH" || symbol == "RETH" || symbol == "WSTETH" || symbol == "WEETH")
} 
