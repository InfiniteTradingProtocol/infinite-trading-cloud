#!/bin/bash

# --- CONFIG ---
MYSQL_HOST="127.0.0.1"
REDIS_HOST="127.0.0.1"
MYSQL_WAIT_SECONDS=5
REDIS_WAIT_SECONDS=2

# --- FUNCTIONS ---
wait_for_mysql() {
  echo "Checking MySQL connection..."
  until mysqladmin ping -h "$MYSQL_HOST" --silent; do
    echo "MySQL not ready. Waiting ${MYSQL_WAIT_SECONDS}s..."
    sleep "$MYSQL_WAIT_SECONDS"
  done
  echo "✅ MySQL is up."
}

wait_for_redis() {
  echo "Checking Redis connection..."
  until redis-cli -h "$REDIS_HOST" ping | grep -q PONG; do
    echo "Redis not ready. Waiting ${REDIS_WAIT_SECONDS}s..."
    sleep "$REDIS_WAIT_SECONDS"
  done
  echo "✅ Redis is up."
}

# --- MAIN LOOP ---
while true; do
  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Running candles thread"

  # Wait for services before starting
  wait_for_mysql
  wait_for_redis

  # Run Python script
  python3 candles.py

  # Optional delay between runs (if needed)
  # sleep 1
done

