#!/bin/bash

while true; do
  echo -e "\nRunning gas balances"
  sleep 5
  python3 gasbalance.py "Infinite Trading Manager" "0x0994fC3C56bEE9783b69De803d201023971F8327" "polygon"
  sleep 5
  python3 gasbalance.py "Infinite Trading Manager" "0x0994fC3C56bEE9783b69De803d201023971F8327" "optimism"
  sleep 5
  python3 gasbalance.py "Infinite Trading Manager" "0x0994fC3C56bEE9783b69De803d201023971F8327" "arbitrum"
  sleep 5
  python3 gasbalance.py "Infinite Trading Trader" "0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5" "optimism"
  sleep 5
  python3 gasbalance.py "Infinite Trading Trader" "0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5" "polygon"
  sleep 5
  python3 gasbalance.py "Infinite Trading Trader" "0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5" "arbitrum"
  sleep 7200
done
