#!/bin/bash

# Script to delete duplicate PM2 processes
# Keeps the newer instance of each duplicate process

echo "🔍 Checking for duplicate PM2 processes..."

# Define the duplicate process IDs to delete (older instances)
DUPLICATES_TO_DELETE=(
  "18"  # pools-monitor (keep id 9)
  "19"  # prices-monitor (keep id 12)
  "23"  # strategy-aero-ema-crossover (keep id 16)
  "31"  # strategy-crossovers (keep id 24)
  "30"  # strategy-op-probability (keep id 21)
  "27"  # strategy-supertrend (keep id 20)
  "26"  # strategy-velo1d-bot (keep id 17)
  "29"  # tradebot (keep id 14)
  "22"  # yields-monitor (keep id 13)
)

echo "🗑️  Deleting duplicate PM2 processes..."
for id in "${DUPLICATES_TO_DELETE[@]}"; do
  echo "  Deleting PM2 process ID: $id"
  pm2 delete "$id"
done

echo "✅ Duplicate processes deleted!"
echo ""
echo "📋 Current PM2 processes:"
pm2 list

echo ""
echo "💾 Saving PM2 configuration..."
pm2 save

echo "✅ Done!"
