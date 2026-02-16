import requests

# Dictionary mapping channel names to webhook URLs
WEBHOOK_URLS = {
    "#pools-trading": "https://discord.com/api/webhooks/1179798763557101590/OVIjOgz-PC1820wpV9BfIzhUplkF3UFqhkF9h6jIsm-nMd9ZqHvwVYMAM3wLxamP3DuO",
    "#dhedge-pools": "https://discordapp.com/api/webhooks/1067155508521336912/k1NiM7RIHvg1uFTDT8CNnhN6hu4TA3WtXa9guMoVlRoRNYUdpTPVViOOeQa36cLxW5e-",
    "#gas": "https://hooks.slack.com/services/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",
    "#market-overview": "https://discordapp.com/api/webhooks/1181332744018595911/H6ybfkKfB5VErtWfKMtAKG76Qnx1P9IwSWMxcL_-Om9sTtuIhetA3uEpkRm8oHNj0tom",
    "#price-alerts": "https://discordapp.com/api/webhooks/1191098131006369852/JmLPU-qQ6cGMRSyRt6Hdbc2G0891So9S9CsI_o0U1fTkaqimz9clObSwIy6ipq5cImHg",
    "#gas-tanks": "https://discord.com/api/webhooks/1191115436771782748/F1utg1naCY157jGJA8EcE3axbYzWWy5JwCUg4CnYyluAncYL2e61NYVYOo9UiF92uU2c",
    "#defund-pools": "https://discord.com/api/webhooks/1191118124083335198/Jxp2leXsHSiZ8L0TiH-CGdqP7LSplBEhdDglBBcJ5KgyAOaEH5-7eoP1JPJgecYRwn0e",
    "#error-logs": "https://discord.com/api/webhooks/1198667998072938638/On1V4W3AslWkZFsAh1ThYuWlH4x4vWZDq7rRiO6UOXkF_zjfyzttvPmUFDJPvHpGcI4t",
    "#signals": "https://discordapp.com/api/webhooks/1208547214410907778/f67Z4rJwtzXkHm6-4ahsyTZNPRE_8d7Tq8COUzpiWpNvL6zsvzhkI-OhL6YpsiPXXgXj",
    "#defi-prices": "https://discord.com/api/webhooks/1205534159888449576/vNS2h3eRsr8ENNI-9TPyK2W49nDWclkWLN1jk71LHlMlSdHYE1nHcZYxZqc2ZM4Pr2mE",
    "#api-logs": "https://discord.com/api/webhooks/1233193167600226304/8cTTyDgdDzjUAXXRApFhXKQ-oHRB0vVk3irYHShUUNLQUbdelQ-6CPy8VfA76xMBDQCy",
    "#api-pools": "https://discord.com/api/webhooks/1304406988427362387/v2-adP4V9JRQfxwRKqGZRDz6CWOFpd8tSpozyviPwzZauAisLY17CHnrybPvS8ACHzve"
}

# Function to get webhook URL based on channel
def get_webhook_url(channel):
    return WEBHOOK_URLS.get(channel, None)

# Function to send a message to the appropriate platform
def send_message(message, channel, platform):
    url = get_webhook_url(channel)
    if not url:
        print("Invalid or unsupported channel.")
        return

    payload = {
        "text" if platform == "slack" else "content": message
    }

    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()  # Will raise an exception for bad status codes
        print("Message sent successfully.")
    except requests.exceptions.RequestException as e:
        print(f"Error sending message: {e}")
        if response is not None:
            print("Status code:", response.status_code)
            print("Response:", response.text)

