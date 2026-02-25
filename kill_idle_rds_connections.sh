#!/bin/bash
# Kill RDS connections idle > 5 minutes
mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com -u admin -pNcwbBmT5Vxv9ZAx infinitetrading -e "
SELECT CONCAT('KILL ', id, ';')
FROM information_schema.processlist 
WHERE user = 'admin' AND command = 'Sleep' AND time > 300 AND id != CONNECTION_ID()
" 2>/dev/null | grep KILL | mysql -h infinitetrading.c9g9hq0ddskg.us-east-2.rds.amazonaws.com -u admin -pNcwbBmT5Vxv9ZAx infinitetrading 2>/dev/null
