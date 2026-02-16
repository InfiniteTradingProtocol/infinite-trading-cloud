from pushpop import pop_message, push_message
from send_messages import send_message

import time
while True:
    res_slack = pop_message(platform="slack")
    res_discord = pop_message(platform="discord")
    if res_discord:
        discord_channel, discord_message = res_discord
        send_message(message=discord_message,channel=discord_channel,platform="discord")
        print("Discord Channel:", discord_channel)
        print("Discord Message:", discord_message)
    if res_slack:
        slack_channel, slack_message = res_slack
        send_message(message=slack_message,channel=slack_channel,platform="slack")
        print("Slack Channel:", slack_channel)
        print("Slack Message:", slack_message)
    time.sleep(1)
