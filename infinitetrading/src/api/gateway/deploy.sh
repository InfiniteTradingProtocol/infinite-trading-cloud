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

tmpfile="$(mktemp)"
cat > "$tmpfile" <<EOF
# Auto-generated; do not edit by hand
# All endpoints route to API Gateway (port 8003)
location ~ ^/(?:$regex)/?$ {
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

    proxy_pass http://localhost:8003;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF

# Write with root permissions
sudo tee "$TARGET" >/dev/null < "$tmpfile"
rm -f "$tmpfile"

# Validate and reload
echo "Validating nginx config..."
sudo nginx -t
echo "Reloading nginx..."
sudo systemctl reload nginx
echo "Done. Wrote allowlist to $TARGET"
