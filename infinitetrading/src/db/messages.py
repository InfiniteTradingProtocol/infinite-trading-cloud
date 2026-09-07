"""
messages.py — message queue collector (PM2: messages-collector).

Drains the `messages` table and delivers every entry to Telegram.

The queue still stores a `platform` column ("discord"/"slack") because ~70
callers across the R strategies and Python scripts write it. Both are now
delivered to Telegram; the platform value survives only as a routing key in
the queue, and both are popped here so no producer's messages can pile up
undelivered.
"""

import time

from pushpop_local import pop_message
from send_messages import send_message

# Legacy queue keys. Both drain to Telegram -- see module docstring.
QUEUES = ("discord", "slack")

# Telegram throttles a single chat at roughly one message per second and answers
# 429 for anything faster, which silently loses the message. Draining a backlog
# as fast as the database can serve it therefore delivers only the first few
# messages. Pace sends instead.
MIN_SECONDS_BETWEEN_SENDS = 1.2

# How long to wait when both queues are empty. Kept short so a new message is
# picked up promptly.
IDLE_SLEEP_SECONDS = 1

print("[MESSAGE COLLECTOR] Starting: draining queues to Telegram...")

last_send = 0.0

while True:
    delivered = False
    for queue in QUEUES:
        res = pop_message(platform=queue)
        if res:
            channel, message = res

            # Space sends out rather than firing back-to-back.
            elapsed = time.monotonic() - last_send
            if elapsed < MIN_SECONDS_BETWEEN_SENDS:
                time.sleep(MIN_SECONDS_BETWEEN_SENDS - elapsed)

            send_message(message=message, channel=channel)
            last_send = time.monotonic()
            print(f"Queue: {queue} | Channel: {channel} | Message: {message}", flush=True)
            delivered = True
    # Only sleep when both queues were empty, so a backlog drains promptly.
    if not delivered:
        time.sleep(IDLE_SLEEP_SECONDS)
