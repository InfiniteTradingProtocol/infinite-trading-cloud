library(httr)
library(dotenv)

# load .env into R session
load_dot_env("~/infinitetrading/src/.env")
TG_CHAT_ID= Sys.getenv("TG_CHAT_ID")
TG_BOT = Sys.getenv("TG_BOT")
send_telegram_text <- function(text, chat_id = NULL,
                               token = TG_BOT,
                               parse_mode = NULL) {
  if (is.null(chat_id)) { chat_id = TG_CHAT_ID }
  url <- sprintf("https://api.telegram.org/bot%s/sendMessage", token)
  body <- list(chat_id = chat_id, text = text)
  if (!is.null(parse_mode)) body$parse_mode <- parse_mode  # "MarkdownV2" or "HTML"
  resp <- POST(url, body = body, encode = "form")
  stop_for_status(resp)
  invisible(content(resp, "parsed"))
}

#send_telegram_text("Hello from R 👋")
