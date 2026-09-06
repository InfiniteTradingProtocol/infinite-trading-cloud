wd = "~/infinitetrading/src/"
source(paste0(wd,"db.R"))

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
        if (channel == "#pools") { ep = "1067155508521336912/k1NiM7RIHvg1uFTDT8CNnhN6hu4TA3WtXa9guMoVlRoRNYUdpTPVViOOeQa36cLxW5e-" }
	else if (channel == "#pools-trading") { ep = "1179798763557101590/OVIjOgz-PC1820wpV9BfIzhUplkF3UFqhkF9h6jIsm-nMd9ZqHvwVYMAM3wLxamP3DuO" }
	else if (channel == "#market-overview") { ep = "1181332744018595911/H6ybfkKfB5VErtWfKMtAKG76Qnx1P9IwSWMxcL_-Om9sTtuIhetA3uEpkRm8oHNj0tom" }	
	else if (channel == "#price-alerts") { ep = "1191098131006369852/JmLPU-qQ6cGMRSyRt6Hdbc2G0891So9S9CsI_o0U1fTkaqimz9clObSwIy6ipq5cImHg" }
	else if (channel == "#api-logs") { ep = "1233193167600226304/8cTTyDgdDzjUAXXRApFhXKQ-oHRB0vVk3irYHShUUNLQUbdelQ-6CPy8VfA76xMBDQCy" }
	else { ep = "1233193167600226304/8cTTyDgdDzjUAXXRApFhXKQ-oHRB0vVk3irYHShUUNLQUbdelQ-6CPy8VfA76xMBDQCy" }  # Default fallback for unknown channels
    	full_url <- paste0(url, ep)
    	response <- POST(full_url, body = list(content = msg), encode = "json")
    	if (http_status(response)$category == "success") { print("Message sent successfully!") }
	else { print(paste("Failed to send message:", http_status(response)$reason)) }
}

slack_webhook = function(channel) { 
  if (channel == "#clarebot-trades") { "https://hooks.slack.com/services/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" }
  else if (channel == "#signals") { "https://hooks.slack.com/services/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" } 
  else if (channel == "#forecast") { "https://hooks.slack.com/services/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"  }
  else if (channel == "#forecast-4h") { "https://hooks.slack.com/services/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" }
  else if (channel == "#returns-reports") { "https://hooks.slack.com/services/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" }
  else if (channel == "#trade-logs") { "https://hooks.slack.com/services/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" }
  else if (channel == "#tradebot-error-logs") { "https://hooks.slack.com/services/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" }
  else if (channel == "#models-probabilities") { "https://hooks.slack.com/services/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" }
  else if (channel == "#ccxt-tradebot-logs") { "https://hooks.slack.com/services/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" }
  else if (channel == "#allocations") { "https://hooks.slack.com/services/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" }
  else if (channel == "#ccxt-wallets") { "https://hooks.slack.com/services/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" }
  else if (channel == "#tradefi") { "https://hooks.slack.com/services/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" }
  else if (channel == "#richport-subaccounts") {"https://hooks.slack.com/services/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"}
  else if (channel == "#stoploss_prices") { "https://hooks.slack.com/services/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" }
  else if (channel == "#alphasigma-subaccounts") { "https://hooks.slack.com/services/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" }
  else if (channel == "#richard-subaccounts") { "https://hooks.slack.com/services/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" }
  else if (channel == "#tradery-subaccounts") {"https://hooks.slack.com/services/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" } 
  else if (channel == "#richport-trading") { "https://hooks.slack.com/services/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" }
  else if (channel == "#tradery-trading") { "https://hooks.slack.com/services/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" }
  else if (channel == "#gas-tanks") { "https://hooks.slack.com/services/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" }
  else if (channel == "#alphasigma-trading") { "https://hooks.slack.com/services/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" }
  else if (channel == "#models") { "https://hooks.slack.com/services/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" }
}
slack_message = function(SlackBot, channel) { 
	require(slackr)
	slackr_bot(SlackBot,incoming_webhook_url=slack_webhook(channel))
}
slack_token = function() { "xoxb-239465774673-915727711137-dI9PeJOsYZNSpPGL61OYlycN" }

