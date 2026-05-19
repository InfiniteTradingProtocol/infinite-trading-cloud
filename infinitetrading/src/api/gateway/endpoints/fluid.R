# Fluid (fToken) sub-router
# Endpoints: POST /fluid/lend  POST /fluid/unlend
# Sanitisation: basic_check() validates apiKey, network (from DB cache), pool address.
#               isValidEthereumAddress() validates the asset token address.
#               Market (fToken address) is auto-derived from asset by the Express layer.
# Forwarding:   Calls Express API (ep = localhost:8000) depositFluid / withdrawFluid.

fluid <- Plumber$new()

fluid$handle("POST", "/lend",
  function(apiKey, protocol = "dhedge", pool, network, asset, share = 100, amount = NULL) {
    protocol <- tolower(trimws(protocol))
    pool     <- tolower(trimws(pool))
    network  <- tolower(trimws(network))

    check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
    if (check$status == "fail") return(check)

    if (!isValidEthereumAddress(asset))
      return(list(status = "fail", status_code = 1004, message = "Invalid asset address"))
    asset <- tolower(asset)

    url <- paste0(ep, "depositFluid",
                  "?apiKey=",  apiKey,
                  "&network=", network,
                  "&pool=",    pool,
                  "&asset=",   asset)

    share_num  <- suppressWarnings(as.numeric(share))
    amount_num <- suppressWarnings(as.numeric(amount))

    if (!is.null(amount) && !is.na(amount_num) && is.finite(amount_num) && amount_num > 0) {
      url <- paste0(url, "&amount=", round(amount_num, 6))
    } else if (!is.null(share) && !is.na(share_num) && is.finite(share_num) &&
               share_num > 0 && share_num <= 100) {
      url <- paste0(url, "&share=", round(share_num, 2))
    } else {
      return(list(status = "fail", status_code = 1009,
                  message = "Please specify share (1-100) or amount (>0)"))
    }

    response <- POST(url)
    txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
    if (status_code(response) == 200) {
      parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
      return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
    }
    return(list(status = "fail", status_code = status_code(response),
                message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
  },
  comment = "Supply an asset to Fluid (fToken vault) within a dHEDGE vault. The fToken market is auto-resolved from the asset address. Specify share (% of vault asset balance, 1-100) or a fixed amount."
)

fluid$handle("POST", "/unlend",
  function(apiKey, protocol = "dhedge", pool, network, asset, share = 100, amount = NULL) {
    protocol <- tolower(trimws(protocol))
    pool     <- tolower(trimws(pool))
    network  <- tolower(trimws(network))

    check <- basic_check(network = network, protocol = protocol, pool = pool, apiKey = apiKey)
    if (check$status == "fail") return(check)

    if (!isValidEthereumAddress(asset))
      return(list(status = "fail", status_code = 1004, message = "Invalid asset address"))
    asset <- tolower(asset)

    url <- paste0(ep, "withdrawFluid",
                  "?apiKey=",  apiKey,
                  "&network=", network,
                  "&pool=",    pool,
                  "&asset=",   asset)

    share_num  <- suppressWarnings(as.numeric(share))
    amount_num <- suppressWarnings(as.numeric(amount))

    if (!is.null(amount) && !is.na(amount_num) && is.finite(amount_num) && amount_num > 0) {
      url <- paste0(url, "&amount=", round(amount_num, 6))
    } else if (!is.null(share) && !is.na(share_num) && is.finite(share_num) &&
               share_num > 0 && share_num <= 100) {
      url <- paste0(url, "&share=", round(share_num, 2))
    } else {
      return(list(status = "fail", status_code = 1009,
                  message = "Please specify share (1-100) or amount (>0)"))
    }

    response <- POST(url)
    txt <- tryCatch(content(response, "text", encoding = "UTF-8"), error = function(e) "N/A")
    if (status_code(response) == 200) {
      parsed <- tryCatch(jsonlite::fromJSON(txt), error = function(e) NULL)
      return(if (!is.null(parsed)) parsed else list(status = "success", msg = txt))
    }
    return(list(status = "fail", status_code = status_code(response),
                message = tryCatch(jsonlite::fromJSON(txt), error = function(e) txt)))
  },
  comment = "Withdraw (unlend) an asset from Fluid (fToken vault) within a dHEDGE vault. The fToken market is auto-resolved from the asset address. Specify share (% of fToken balance, 1-100) or a fixed amount."
)

# mount onto the main router (relies on `pr` being in scope when sourced)
pr$mount("/fluid", fluid)
