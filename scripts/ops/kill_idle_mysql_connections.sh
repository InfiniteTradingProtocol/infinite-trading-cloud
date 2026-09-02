#!/bin/bash
# Kill local MySQL connections idle > 5 minutes (300 seconds)
# Runs every minute via cron

mysql -u richard_clare -p"$MYSQL_PASSWORD" infinitetrading -e "
SELECT CONCAT('KILL ', id, ';')
FROM information_schema.processlist 
WHERE user = 'richard_clare' 
  AND command = 'Sleep' 
  AND time > 300 
  AND id != CONNECTION_ID()
" 2>/dev/null | grep KILL | mysql -u richard_clare -p"$MYSQL_PASSWORD" infinitetrading 2>/dev/null

# Optional: Log connection count for monitoring
# CONN_COUNT=$(mysql -u richard_clare -p"$MYSQL_PASSWORD" -e "SHOW PROCESSLIST;" | wc -l)
# echo "$(date): Active connections: $CONN_COUNT" >> /tmp/mysql_connections.log
