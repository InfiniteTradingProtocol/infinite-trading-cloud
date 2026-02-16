library(httr)
library(dotenv)

# load .env into R session
# Use wd if set (from parent), otherwise assume current dir
env_path = if (exists("wd")) paste0(wd, ".env") else ".env"
if (file.exists(env_path)) {
  load_dot_env(env_path)
} else {
  warning(paste0("Warning: .env not found at ", env_path))
}
TG_BOT = Sys.getenv("TG_BOT")
send_telegram_report <- function(text, chat_id,
                               token = TG_BOT,
                               parse_mode = NULL) {
  url <- sprintf("https://api.telegram.org/bot%s/sendMessage", token)
  body <- list(chat_id = chat_id, text = text)
  if (!is.null(parse_mode)) body$parse_mode <- parse_mode  # "MarkdownV2" or "HTML"
  resp <- POST(url, body = body, encode = "form")
  stop_for_status(resp)
  invisible(content(resp, "parsed"))
}

#send_telegram_text("Hello from R 👋")
summarize_value <- function(v) {
  # compact summary only; avoid dumping large payloads
  if (is.list(v)) {
    parts <- c()

    # Status with emoji
    if (!is.null(v$status)) {
      s_str <- as.character(v$status)
      s_emoji <- if (tolower(s_str) == "success") "✅ " else if (tolower(s_str) == "fail") "❌ " else "⬜️ "
      parts <- c(parts, paste0(s_emoji, "Response status: ", s_str))
    }

    # Status code with emoji
    if (!is.null(v$status_code)) {
      code_num <- suppressWarnings(as.integer(v$status_code))
      code_emoji <- if (!is.na(code_num) && code_num == 200L) "🟢 " else "🔴 "
      parts <- c(parts, paste0(code_emoji, "Status Code: ", if (!is.na(code_num)) code_num else as.character(v$status_code)))
    }

    # Messages with 📄
    if (!is.null(v$message)) {
      parts <- c(parts, paste0("📄 Response message: ", substr(as.character(v$message), 1, 160)))
    }
    if (!is.null(v$msg)) {
      parts <- c(parts, paste0("📄 Response message: ", substr(as.character(v$msg), 1, 160)))
    }

    if (length(parts)) return(paste(parts, collapse = "\n"))
    return(paste0("list(", paste(utils::head(names(v), 6), collapse = ","), if (length(v) > 6) ",..." else "", ")"))
  }

  if (is.character(v)) return(paste0("📄 Response message: ", substr(v, 1, 160)))
  if (is.raw(v))       return(paste0("raw(", length(v), " bytes)"))
  paste0("type=", paste(class(v), collapse = "|"))
}


send_request_report <- function(req, status = NA_integer_, note = NULL,report="GATEWAY") {
  if (report == "GATEWAY") { chat_id = "-4796436646" }
  # ---- safe getters (base R, no %||%)
  ts   <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  ip   <- if (!is.null(req$HTTP_X_REAL_IP)) req$HTTP_X_REAL_IP else if (!is.null(req$REMOTE_ADDR)) req$REMOTE_ADDR else "0.0.0.0"
  path <- if (!is.null(req$PATH_INFO)) req$PATH_INFO else "/"
  mtd  <- if (!is.null(req$REQUEST_METHOD)) req$REQUEST_METHOD else "GET"
  qs   <- if (!is.null(req$QUERY_STRING)) req$QUERY_STRING else ""
  ua   <- if (!is.null(req$HTTP_USER_AGENT)) req$HTTP_USER_AGENT else ""
  endpoint <- sub("^/+", "", path)

  # ---- parse query string into a named list
  parse_qs <- function(q) {
    if (is.null(q) || !nzchar(q)) return(list())
    q <- sub("^\\?+", "", q)             # handle leading "?" or "??"
    parts <- strsplit(q, "&", fixed = TRUE)[[1]]
    kv <- lapply(parts, function(p) {
      sp <- strsplit(p, "=", fixed = TRUE)[[1]]
      key <- utils::URLdecode(sp[1])
      val <- if (length(sp) > 1) utils::URLdecode(sp[2]) else ""
      c(key = key, value = val)
    })
    out <- list()
    for (i in seq_along(kv)) {
      k <- kv[[i]]["key"]; v <- kv[[i]]["value"]
      # keep last occurrence if duplicated keys
      out[[k]] <- v
    }
    out
  }

  params <- parse_qs(qs)

  # ---- pick out main fields
  network  <- if (!is.null(params$network))  params$network  else "None"
  protocol <- if (!is.null(params$protocol)) params$protocol else "None"
  pool     <- if (!is.null(params$pool))     params$pool     else "None"
  apiKey   <- if (!is.null(params$apiKey))   params$apiKey   else "None"
  masked   <- tryCatch(mask_api(apiKey), error = function(e) "None")

  # everything else as "other params"
  known <- c("network","protocol","pool","apiKey")
  others <- params[setdiff(names(params), known)]

  # ---- emoji helpers (inline to avoid deps)
  emoji_method <- switch(toupper(mtd),
    "GET"="🟦 GET", "POST"="🟩 POST", "PUT"="🟨 PUT", "PATCH"="🟧 PATCH",
    "DELETE"="🟥 DELETE", "HEAD"="⬜ HEAD", "OPTIONS"="🟪 OPTIONS", paste0("⬜ ", mtd))
  emoji_status <- {
    code <- suppressWarnings(as.integer(status))
    if (is.na(code)) "⬜️" else if (code < 200) "⬜️" else if (code < 300) "✅" else if (code < 400) "⚠️" else if (code < 500) "❗" else "🔥"
  }

  # ---- build structured, multi-line message
  # Format requested:
  # POST ENDPOINT
  # network: X / protocol: Y / pool: Z
  # endpoint:
  # apiKey: MASKED
  # otherparams
  other_str <- if (length(others)) {
    paste(paste0(names(others), ": ", unlist(others, use.names = FALSE)), collapse = " / ")
  } else {
    "none"
  }

  msg <- paste0(
    ts, " ", emoji_status, " ", emoji_method, " /", endpoint," TO: ",report, "\n",
    "🌎 Network: ", network, "\n",
    "🔧 Protocol: ", protocol, "\n",
    "⚫ Pool: ", pool, "\n",
    "🔑 API Key: ", masked, "\n",
    "📄 Other: ", other_str, "\n",
    "🌐 IP: ", ip, "\n", 
    if (nzchar(note)) note else ""
  )

  # send + print
  try(send_telegram_report(msg,chat_id=chat_id), silent = TRUE)
  cat(msg, "\n")
}

