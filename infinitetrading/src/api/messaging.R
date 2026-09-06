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
discord = function(msg,channel="#dhedge-pools",db=TRUE) {
        if (db) {
                result = tryCatch({push_message(platform="discord",channel=channel,message=msg); Sys.sleep(0.0001)}, error = function(e) {
                print(paste0("An error ocurred: ", conditionMessage(e)))})
        }
        else { discord_NODB(msg=msg,channel=channel) }
}

discord_NODB = function(msg,channel="#dhedge-pools") {
        require(httr)
        url = "https://discord.com/api/webhooks/"
        if (channel == "#api-logs") { ep = "1233193167600226304/8cTTyDgdDzjUAXXRApFhXKQ-oHRB0vVk3irYHShUUNLQUbdelQ-6CPy8VfA76xMBDQCy" }
        
	full_url <- paste0(url, ep)

        # Prepare the POST request
        response <- POST(full_url, body = list(content = msg), encode = "json")

        # Check response
        if (http_status(response)$category == "success") {
                print("Message sent successfully!")
        } else {
                print(paste("Failed to send message:", http_status(response)$reason))
        }
}
slack_webhook = function(channel) { 
	if (channel == "#gas-tanks") { "https://hooks.slack.com/services/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" }
}
slack_message = function(SlackBot, channel) {
        require(slackr)
        slackr_bot(SlackBot,incoming_webhook_url=slack_webhook(channel))
}
slack_token = function() { "xoxb-239465774673-915727711137-dI9PeJOsYZNSpPGL61OYlycN" }

