wd = "~/infinitetrading/src/"
source(paste0(wd,"db.R"))

# Telegram is the only notification transport. Sourced defensively because the
# callers of this file source it inconsistently and discord() below depends on
# send_telegram_text being defined.
if (!exists("send_telegram_text")) source("~/infinitetrading/src/telegram.R")

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

