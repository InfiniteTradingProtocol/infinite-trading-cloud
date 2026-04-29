#!/bin/bash
# rotate_alchemy_keys.sh
# Updates Alchemy API keys across all EC2 .env files and restarts services.
#
# Usage:
#   ./scripts/rotate_alchemy_keys.sh <new_api_key> <new_balances_key>
#
# Both keys are required. Get new keys from:
#   https://dashboard.alchemy.com → Apps → your app → API Key
#
# Files updated:
#   /home/ubuntu/infinitetrading_api/.env        ALCHEMY_API_KEY, ALCHEMY_BALANCES_KEY
#   /home/ubuntu/infinitetrading/src/.env        ALCHEMY_BALANCES_APIKEY
#   /home/ubuntu/infinitetrading/src/api/.env    ALCHEMY_BALANCES_APIKEY

set -euo pipefail

EC2="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="$HOME/.ssh/macbook.pem"

# --- At least one key is required ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <new_api_key> [new_balances_key]"
  echo ""
  echo "  new_api_key      — replaces ALCHEMY_API_KEY (used by Express for RPC/txns)"
  echo "  new_balances_key — (optional) replaces ALCHEMY_BALANCES_KEY / ALCHEMY_BALANCES_APIKEY"
  echo ""
  echo "Get new keys from: https://dashboard.alchemy.com"
  exit 1
fi

NEW_API_KEY="${1:-}"
NEW_BALANCES_KEY="${2:-}"

echo "================================================"
echo " Alchemy Key Rotation"
[[ -n "$NEW_API_KEY" ]]      && echo " ALCHEMY_API_KEY      → ${NEW_API_KEY:0:8}..."
[[ -n "$NEW_BALANCES_KEY" ]] && echo " ALCHEMY_BALANCES_KEY → ${NEW_BALANCES_KEY:0:8}..."
echo "================================================"
echo ""

echo "[1/3] Stopping services..."
ssh -i "$SSH_KEY" "$EC2" "pm2 stop infinitetrading-api plumber-api api-gateway && echo '  Services stopped.'"

echo ""
echo "[2/3] Updating .env files on EC2..."

ssh -i "$SSH_KEY" "$EC2" NEW_API_KEY="${NEW_API_KEY}" NEW_BALANCES_KEY="${NEW_BALANCES_KEY}" bash <<'ENDSSH'
set -e

update_env() {
  local file="$1"
  local var="$2"
  local val="$3"
  if [[ ! -f "$file" ]]; then
    echo "  SKIP (not found): $file"
    return
  fi
  if grep -qE "^${var}=" "$file" 2>/dev/null; then
    sed -i "s|^${var}=.*|${var}=\"${val}\"|" "$file"
    echo "  UPDATED $var in $file"
  else
    echo "  SKIP (var not present): $var in $file"
  fi
}

# Express .env — main API key + balances key
[[ -n "$NEW_API_KEY" ]]      && update_env "/home/ubuntu/infinitetrading_api/.env"     "ALCHEMY_API_KEY"      "$NEW_API_KEY"
[[ -n "$NEW_BALANCES_KEY" ]] && update_env "/home/ubuntu/infinitetrading_api/.env"     "ALCHEMY_BALANCES_KEY" "$NEW_BALANCES_KEY"

# R .env files — balances key only
[[ -n "$NEW_BALANCES_KEY" ]] && update_env "/home/ubuntu/infinitetrading/src/.env"     "ALCHEMY_BALANCES_APIKEY" "$NEW_BALANCES_KEY"
[[ -n "$NEW_BALANCES_KEY" ]] && update_env "/home/ubuntu/infinitetrading/src/api/.env" "ALCHEMY_BALANCES_APIKEY" "$NEW_BALANCES_KEY"

echo "  All .env files updated."
ENDSSH

echo ""
echo "[3/3] Restarting services..."
ssh -i "$SSH_KEY" "$EC2" "pm2 start infinitetrading-api plumber-api api-gateway --update-env && echo '  Services started.'"

echo ""
echo "================================================"
echo " Done. Verify with a quick smoke test:"
echo "   curl -s 'https://api.infinitetrading.io/getAllGasBalance?network=base&manager=<addr>&signature=<sig>'"
echo "================================================"
echo ""
echo "  ⚠️  Remember to also:"
echo "    1. Delete the old Alchemy keys from https://dashboard.alchemy.com"
echo "    2. Set domain allowlists on the new keys in Alchemy dashboard"
echo "    3. Rotate any frontend bundle that contains the old key (trigger a redeploy)"
