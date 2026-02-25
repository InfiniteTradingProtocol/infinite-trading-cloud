#!/usr/bin/env bash
set -euo pipefail

OPENAPI_URL="http://127.0.0.1:8003/openapi.json"
TARGET="/etc/nginx/snippets/itp_endpoints.conf"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }

need curl
need jq
need nginx

# Ensure target dir exists (root-owned)
sudo install -d -m 755 /etc/nginx/snippets

# Fetch and build regex from OpenAPI paths
echo "Fetching $OPENAPI_URL ..."
json="$(curl -sf "$OPENAPI_URL")" || { echo "Failed to fetch $OPENAPI_URL"; exit 1; }

regex="$(printf '%s' "$json" \
  | jq -r '.paths | keys[]?' \
  | sed -E 's#^/##' \
  | awk 'NF' \
  | paste -sd'|' -)"

if [ -z "${regex:-}" ]; then
  echo "No paths found in OpenAPI; aborting."
  exit 1
fi

tmpfile="$(mktemp)"
cat > "$tmpfile" <<EOF
# Auto-generated; do not edit by hand
location ~ ^/(?:$regex)/?$ {
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

