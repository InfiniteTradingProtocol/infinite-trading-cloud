#* @param apiKey       API key for authentication
#* @param pool         Vault (pool) address
#* @param network      Network (e.g. "base", "optimism")
#* @param asset1       First token of the pair (address)
#* @param asset2       Second token of the pair (address)
#* @param token_id     UniswapV3 NFT position token ID (integer string)
#* @param platform     DEX platform — only "uniswapv3" supported (default: "uniswapv3")
#* @param amount       Percentage of liquidity to remove, 0-100 (default 100)
#* @param output_asset Output token: "both" | asset1 address | asset2 address | other tracked address
#* @param slippage     Swap slippage tolerance in percent (default 0.5)
#* @param protocol     Protocol — "dhedge" (default)
#* @response 200 Returns transaction hash on success
#* @response 400 Bad request
#* @post /removeLiquidity

removeLiquidityHandler <- function(
  network      = "base",
  protocol     = "dhedge",
  platform     = "uniswapv3",
  apiKey,
  pool,
  asset1,
  asset2,
  token_id,
  amount       = 100,
  output_asset = "both",
  slippage     = 0.5
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

  # token_id: must be a non-negative integer
  if (is.null(token_id) || is.na(token_id)) {
    return(list(status = "fail", status_code = 1011, message = "token_id is required"))
  }
  token_id_clean <- suppressWarnings(as.character(as.integer(token_id)))
  if (is.na(as.integer(token_id))) {
    return(list(status = "fail", status_code = 1011, message = "token_id must be a valid non-negative integer"))
  }

  # amount: percentage (0, 100]
  amount_num <- suppressWarnings(as.numeric(amount))
  if (is.na(amount_num) || !is.finite(amount_num) || amount_num <= 0 || amount_num > 100) {
    return(list(status = "fail", status_code = 1007,
                message = "amount must be a percentage in (0, 100]"))
  }

  # output_asset: "both" or an address (validated by Express)
  output_asset_clean <- trimws(output_asset)
  if (is.null(output_asset_clean) || nchar(output_asset_clean) == 0) {
    output_asset_clean <- "both"
  }

  # Slippage validation
  slippage_num <- suppressWarnings(as.numeric(slippage))
  if (is.na(slippage_num) || slippage_num <= 0 || slippage_num > 50) {
    return(list(status = "fail", status_code = 1008,
                message = "slippage must be in (0, 50]"))
  }

  # Build URL
  url <- paste0(
    pep, "removeLiquidity",
    "?apiKey=",       apiKey,
    "&network=",      network,
    "&pool=",         pool,
    "&platform=",     platform,
    "&asset1=",       asset1,
    "&asset2=",       asset2,
    "&token_id=",     token_id_clean,
    "&amount=",       round(amount_num, 2),
    "&output_asset=", output_asset_clean,
    "&slippage=",     round(slippage_num, 4)
  )

  print(paste0("removeLiquidity gateway url: ", gsub(apiKey, "***", url, fixed = TRUE)))

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
  "POST", "/removeLiquidity", removeLiquidityHandler,
  comment = paste(
    "Remove liquidity from a UniswapV3 position held in a dHEDGE vault.",
    "Specify the token_id (NFT position ID from the vault's UniswapV3 position).",
    "Use amount to remove a percentage (default 100 = full exit).",
    "Set output_asset to 'both' to keep both tokens in the vault,",
    "or to a specific token address to automatically swap the other token's proceeds."
  )
)
