#* @param apiKey      API key for authentication
#* @param pool        Vault (pool) address
#* @param network     Network (e.g. "base", "optimism")
#* @param asset1      First token of the liquidity pair (address)
#* @param asset2      Second token of the liquidity pair (address)
#* @param input_asset Source token used to fund the position (address)
#* @param platform    DEX platform — only "uniswapv3" supported (default: "uniswapv3")
#* @param fee_tier    Fee tier: 500, 3000, or 10000 (default: 3000)
#* @param lower_price Lower price bound for concentrated range (omit for full range)
#* @param upper_price Upper price bound for concentrated range (omit for full range)
#* @param share       Percentage of input_asset balance to use, 1-100 (default 100)
#* @param amount      Explicit token amount to use (overrides share if set)
#* @param slippage    Swap slippage tolerance in percent (default 0.5)
#* @param protocol    Protocol — "dhedge" (default)
#* @response 200 Returns transaction hash on success
#* @response 400 Bad request
#* @post /addLiquidity

addLiquidityHandler <- function(
  network     = "base",
  protocol    = "dhedge",
  platform    = "uniswapv3",
  apiKey,
  pool,
  asset1,
  asset2,
  input_asset,
  fee_tier    = 3000,
  lower_price = NULL,
  upper_price = NULL,
  share       = 100,
  amount      = NULL,
  slippage    = 0.5
) {
  network  <- tolower(trimws(network))
  protocol <- tolower(trimws(protocol))
  platform <- tolower(trimws(platform))

  # Basic authentication + network/protocol validation
  check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
  if (check$status == "fail") return(check)

  # Platform whitelist
  if (!platform %in% c("uniswapv3")) {
    return(list(status = "fail", status_code = 1010,
                message = paste0("Unsupported platform: ", platform, ". Supported: uniswapv3")))
  }

  # fee_tier whitelist
  fee_tier_int <- suppressWarnings(as.integer(fee_tier))
  if (is.na(fee_tier_int) || !fee_tier_int %in% c(500L, 3000L, 10000L)) {
    return(list(status = "fail", status_code = 1011,
                message = "fee_tier must be one of: 500, 3000, 10000"))
  }

  # share / amount validation
  share_num  <- suppressWarnings(as.numeric(share))
  amount_num <- suppressWarnings(as.numeric(amount))

  if (!is.null(amount) && !is.na(amount_num)) {
    if (!is.finite(amount_num) || amount_num <= 0) {
      return(list(status = "fail", status_code = 1007,
                  message = "amount must be a positive number"))
    }
  } else if (!is.null(share) && !is.na(share_num)) {
    if (!is.finite(share_num) || share_num <= 0 || share_num > 100) {
      return(list(status = "fail", status_code = 1007,
                  message = "share must be in (0, 100]"))
    }
  }

  # Slippage validation
  slippage_num <- suppressWarnings(as.numeric(slippage))
  if (is.na(slippage_num) || slippage_num <= 0 || slippage_num > 50) {
    return(list(status = "fail", status_code = 1008,
                message = "slippage must be in (0, 50]"))
  }

  # Build URL
  url <- paste0(
    pep, "addLiquidity",
    "?apiKey=",      apiKey,
    "&network=",     network,
    "&pool=",        pool,
    "&platform=",    platform,
    "&asset1=",      asset1,
    "&asset2=",      asset2,
    "&input_asset=", input_asset,
    "&fee_tier=",    fee_tier_int,
    "&slippage=",    round(slippage_num, 4)
  )

  # Optional amount overrides share
  if (!is.null(amount) && !is.na(amount_num) && is.finite(amount_num) && amount_num > 0) {
    url <- paste0(url, "&amount=", amount)
  } else if (!is.null(share) && !is.na(share_num) && is.finite(share_num)) {
    url <- paste0(url, "&share=", round(share_num, 2))
  }

  # Optional price range
  if (!is.null(lower_price) && !is.na(lower_price)) {
    url <- paste0(url, "&lower_price=", as.numeric(lower_price))
  }
  if (!is.null(upper_price) && !is.na(upper_price)) {
    url <- paste0(url, "&upper_price=", as.numeric(upper_price))
  }

  print(paste0("addLiquidity gateway url: ", gsub(apiKey, "***", url, fixed = TRUE)))

  response <- POST(url)
  txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
  if (status_code(response) == 200) {
    parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
    return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
  }
  list(
    status      = "fail",
    status_code = status_code(response),
    message     = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)
  )
}

pr$handle(
  "POST", "/addLiquidity", addLiquidityHandler,
  comment = paste(
    "Add liquidity to a UniswapV3 pool through a dHEDGE vault.",
    "Provide input_asset (the source token you want to use), asset1 and asset2 (the pair tokens),",
    "and optionally lower_price/upper_price for a concentrated position (full range by default).",
    "The input_asset is automatically split and swapped to the correct ratio before providing liquidity.",
    "Use fee_tier 500 for stable pairs, 3000 for most pairs, 10000 for exotic pairs."
  )
)
