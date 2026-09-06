#!/usr/bin/env bash
set -euo pipefail

ENDPOINTS_FILE="$HOME/infinitetrading/src/api/helpers/endpoints.R"
TARGET="/etc/nginx/snippets/itp_endpoints.conf"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need nginx

# Ensure target dir exists (root-owned)
sudo install -d -m 755 /etc/nginx/snippets

# Extract ALL endpoints from endpoints.R (including hidden ones)
echo "Reading all endpoints from $ENDPOINTS_FILE ..."
regex="$(grep -E '^\s*"[^"]+"\s*,?\s*$' "$ENDPOINTS_FILE" | sed -E 's/^\s*"([^"]+)"\s*,?\s*$/\1/' | sort -u | paste -sd'|' -)"

if [ -z "${regex:-}" ]; then
  echo "No endpoints found in $ENDPOINTS_FILE; aborting."
  exit 1
fi

echo "Generated regex with $(echo "$regex" | tr '|' '\n' | wc -l) endpoints"

# The R gateway (port 8003) and plumber API (port 8002) were retired once the
# migration to Express completed; both are removed from PM2 and nothing
# listens on those ports. EVERY endpoint therefore routes to Express on 8000.
#
# This script used to take a CUTOVER_ENDPOINTS list and send anything absent
# from it to port 8003. With R gone, that default ("route everything to R")
# regenerated a config pointing the whole API at a dead port -- running it
# unmodified took production down. The dual-backend logic is deleted rather
# than defaulted, so it cannot come back.
express_regex="$regex"

tmpfile="$(mktemp)"
{
cat <<EOF
# Auto-generated; do not edit by hand
# All endpoints route to the Express service on port 8000.
location ~ ^/(?:$express_regex)(?:/[^/]+)?/?\$ {
    limit_req zone=api burst=20 nodelay;
    if (\$arg_apiKey = "vault42") { return 444; }
    if (\$query_string ~* "(%60|\`|api_tokens|encrypted_pk|union%20|select%20|where%20|%27|--|%2d%2d|/\\*|%2f%2a)") { return 444; }

    # CORS headers
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, PUT, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, Accept, X-Requested-With' always;

    # Handle preflight OPTIONS request
    if (\$request_method = 'OPTIONS') {
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, DELETE, PUT, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, Accept, X-Requested-With';
        add_header 'Access-Control-Max-Age' 1728000;
        add_header 'Content-Type' 'text/plain; charset=utf-8';
        add_header 'Content-Length' 0;
        return 204;
    }

    proxy_pass http://localhost:8000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF
} > "$tmpfile"

# Write with root permissions
sudo tee "$TARGET" >/dev/null < "$tmpfile"
rm -f "$tmpfile"

# Refuse to install a config that points at a backend nothing is listening on.
# nginx -t only checks syntax, so a config aimed at a dead port passes cleanly
# and then 502s every request -- which is exactly how this script once caused
# an outage.
if ! (exec 3<>/dev/tcp/127.0.0.1/8000) 2>/dev/null; then
  echo "ABORT: nothing is listening on 127.0.0.1:8000 (the Express API)." >&2
  echo "Start it first:  pm2 start infinitetrading-api" >&2
  exit 1
fi

# Validate and reload
echo "Validating nginx config..."
sudo nginx -t
echo "Reloading nginx..."
sudo systemctl reload nginx
echo "Done. Wrote allowlist to $TARGET"
