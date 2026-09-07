"""
send_messages.py — outbound notification transport.

ALL notifications go to Telegram. Discord and Slack were retired; their
webhooks have been removed from this file rather than left dormant, because
they were live credentials committed in plaintext.

WHY THIS KEEPS THE `platform` / `channel` ARGUMENTS
---------------------------------------------------
Roughly 70 call sites across the R strategies, the tradebot and the Python
DeFi scripts call discord()/push_message() with a channel like "#error-logs".
Rewriting all of them would mean touching every live trading strategy at once.
Instead the transport is retargeted here: the queue and its callers are
unchanged, and `channel` is now used as a subject prefix on the Telegram
message so the origin of an alert is still visible ("[#error-logs] ...").

`platform` is accepted and ignored. It stays in the signature so existing
callers and already-queued rows keep working; everything goes to Telegram.
"""

import os
import time

import requests
from dotenv import load_dotenv

# Callers run from several working directories, so resolve the .env relative to
# this file rather than the cwd.
load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env"))

TG_BOT = os.getenv("TG_BOT")
TG_CHAT_ID = os.getenv("TG_CHAT_ID")

TELEGRAM_MAX_CHARS = 4096


def send_message(message, channel=None, platform=None):
    """Deliver a notification to Telegram.

    `channel` is prepended as a tag so the alert's origin stays visible.
    `platform` is ignored (see module docstring) and retained only for
    backwards compatibility with existing callers.
    """
    if not TG_BOT or not TG_CHAT_ID:
        print("[TELEGRAM] TG_BOT or TG_CHAT_ID not configured; message dropped.")
        return False

    text = f"[{channel}] {message}" if channel else str(message)
    if len(text) > TELEGRAM_MAX_CHARS:
        text = text[: TELEGRAM_MAX_CHARS - 3] + "..."

    # Telegram answers 429 with a retry_after when a chat is sent to too
    # quickly. Honour it rather than dropping the notification -- the collector
    # has already deleted the row from the queue, so a lost send is lost for
    # good.
    for attempt in range(3):
        try:
            response = requests.post(
                f"https://api.telegram.org/bot{TG_BOT}/sendMessage",
                data={"chat_id": TG_CHAT_ID, "text": text},
                timeout=15,
            )
            if response.status_code == 429:
                retry_after = 1
                try:
                    retry_after = int(response.json()["parameters"]["retry_after"])
                except Exception:
                    pass
                if attempt < 2:
                    print(f"[TELEGRAM] Rate limited; retrying in {retry_after + 1}s")
                    time.sleep(retry_after + 1)
                    continue
            response.raise_for_status()
            print("Message sent successfully.")
            return True
        except requests.exceptions.RequestException as e:
            if attempt < 2 and getattr(e, "response", None) is None:
                # Transient network error: one more try before giving up.
                time.sleep(1)
                continue
            return _report_failure(e)
    return False


def _report_failure(e):
    """Log a delivery failure. Never raises: a failed notification must not
    abort the trading action that triggered it."""
    print(f"Error sending message: {e}")
    response = getattr(e, "response", None)
    if response is not None:
        print("Status code:", response.status_code)
        print("Response:", response.text)
    return False
