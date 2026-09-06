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

print("[MESSAGE COLLECTOR] Starting: draining queues to Telegram...")

while True:
    delivered = False
    for queue in QUEUES:
        res = pop_message(platform=queue)
        if res:
            channel, message = res
            send_message(message=message, channel=channel)
            print(f"Queue: {queue} | Channel: {channel} | Message: {message}")
            delivered = True
    # Only sleep when both queues were empty, so a backlog drains promptly.
    if not delivered:
        time.sleep(1)
