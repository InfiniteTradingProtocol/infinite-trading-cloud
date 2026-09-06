library(httr)
library(dotenv)

# load .env into R session
load_dot_env(".env")
TG_CHAT_ID= Sys.getenv("TG_CHAT_ID")
TG_BOT = Sys.getenv("TG_BOT")
send_telegram_text <- function(text, chat_id = TG_CHAT_ID,
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
# NOTIFICATIONS: everything goes to Telegram. Discord and Slack were retired.
# The function is still named discord() because ~70 call sites across the
# strategies and tradebot invoke it; retargeting the transport here avoids
# editing every live trading strategy. `channel` is kept and used as a tag so
# the origin of an alert stays visible, and `db` still selects queued delivery
# (via the messages table, drained by messages-collector) versus sending inline.
discord = function(msg,channel="#dhedge-pools",db=TRUE) {
        if (db) {
                result = tryCatch({push_message(platform="discord",channel=channel,message=msg); Sys.sleep(0.0001)}, error = function(e) {
                print(paste0("An error ocurred: ", conditionMessage(e)))})
        }
        else { discord_NODB(msg=msg,channel=channel) }
}

# Inline (unqueued) Telegram send. Never raises: a failed notification must not
# abort the trading action that triggered it.
discord_NODB = function(msg,channel="#dhedge-pools") {
        tryCatch({
                send_telegram_text(paste0("[", channel, "] ", msg))
                print("Message sent successfully!")
        }, error = function(e) {
                print(paste0("Failed to send message: ", conditionMessage(e)))
        })
}
# Slack was retired along with Discord; everything goes to Telegram. The
# function name and `channel` argument are kept because ~30 call sites in the
# tradebot files use them, and `channel` still tags the message's origin.
slack_message = function(SlackBot, channel="#tradebot-error-logs") {
        tryCatch({
                send_telegram_text(paste0("[", channel, "] ", paste(SlackBot, collapse=" ")))
        }, error = function(e) {
                print(paste0("Failed to send message: ", conditionMessage(e)))
        })
}

