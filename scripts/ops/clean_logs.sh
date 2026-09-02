#!/bin/bash
# Script to delete MySQL binary logs older than 7 days

# Path to MySQL binary logs
BINLOG_PATH="/var/lib/mysql/"

# Find and delete binary logs older than 7 days
find $BINLOG_PATH -name 'binlog.*' -type f -mtime +2 -exec rm -f {} \;

