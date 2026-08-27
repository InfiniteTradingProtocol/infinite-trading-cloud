#!/usr/bin/env bash
set -euo pipefail

OPENAPI_URL="http://127.0.0.1:8003/openapi.json"
TARGET="/etc/nginx/snippets/itp_endpoints.conf"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1"; exit 1; }; }
need curl
need jq
need nginx

sudo install -d -m 755 /etc/nginx/snippets

echo "Fetching $OPENAPI_URL ..."
json="$(curl -sf "$OPENAPI_URL")" || { echo "Failed to fetch $OPENAPI_URL"; exit 1; }

# Build a JSON object:
# {
#   "ROOT": ["approve","borrow",...],
#   "aaveV3": ["getBorrowed","getSupplied","lend", ...],
#   "otherPrefix": ["foo","bar/baz", ...]
# }
grouped="$(printf '%s' "$json" \
  | jq -r '
    (.paths // {}) | keys
    | map(ltrimstr("/"))
    | map(
        if index("/") == null then
          {k:"ROOT", v:.}
        else
          {k:(.[:index("/")]), v:(.[index("/")+1:])}
        end
      )
    | group_by(.k)
    | map({
        (.[0].k): (map(.v)
          # Filter out empty remainders (just in case)
          | map(select(length>0))
        )
      })
    | add
  ')"

# Nothing to do?
if [[ -z "$grouped" || "$grouped" == "null" ]]; then
  echo "No paths found in OpenAPI; aborting."
  exit 1
fi

# Simple regex-escape for NGINX PCRE (escape: .+*?^$()[]{}|\ )
escape_regex() {
  sed -E 's/([][().^$|*+?{}\\])/\\\1/g'
}

# Emit a single location block given: prefix + array of remainders
emit_block() {
  local prefix="$1"; shift
  local items_json="$1"; shift

  # Read array into bash lines
  mapfile -t ITEMS < <(printf '%s' "$items_json" | jq -r '.[]' 2>/dev/null || true)

  # Skip empty groups
  ((${#ITEMS[@]})) || return 0

  # Escape each item for regex alternation
  local escaped_items=()
  for it in "${ITEMS[@]}"; do
    # prevent accidental empty | alternations
    [[ -z "$it" ]] && continue
    escaped_items+=( "$(printf '%s' "$it" | escape_regex)" )
  done
  ((${#escaped_items[@]})) || return 0

  local alternation
  alternation="$(IFS='|'; echo "${escaped_items[*]}")"

  # Build the pattern
  # ROOT => ^/(?:item1|item2)/?$
  # prefix p => ^/p/(?:item1|item2)/?$
  local pat
  if [[ "$prefix" == "ROOT" ]]; then
    pat="^/(?:$alternation)/?$"
  else
    # If some items contain slashes (e.g. "foo/bar"), this still works because we’re
    # alternating the remainder after "/prefix/" verbatim.
    pat="^/$(printf '%s' "$prefix" | escape_regex)/(?:$alternation)/?$"
  fi

  cat <<BLOCK
location ~ $pat {
    if (\$arg_apiKey = "vault42") { return 444; }
    if (\$query_string ~* "(%60|`|api_tokens|encrypted_pk|union%20|select%20|where%20|%27|--|%2d%2d|/\\*|%2f%2a)") { return 444; }

    proxy_pass http://localhost:8003;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
BLOCK
}

tmpfile="$(mktemp)"

{
  echo "# Auto-generated; do not edit by hand"
  # Emit A) non-ROOT groups first (e.g., aaveV3), then B) ROOT at the end
  # This order is mostly stylistic; regex locations of equal precedence match the first defined.
  # We put grouped prefixes first for readability.
  # 1) Non-ROOT
  printf '%s' "$grouped" | jq -r 'to_entries | map(select(.key!="ROOT")) | .[] | @base64' |
  while read -r row; do
    kv="$(printf '%s' "$row" | base64 --decode)"
    k="$(printf '%s' "$kv" | jq -r '.key')"
    v="$(printf '%s' "$kv" | jq -c '.value')"
    emit_block "$k" "$v"
  done
  # 2) ROOT (if any)
  if printf '%s' "$grouped" | jq -e 'has("ROOT") and (.ROOT | length>0)' >/dev/null; then
    emit_block "ROOT" "$(printf '%s' "$grouped" | jq -c '.ROOT')"
  fi
} > "$tmpfile"

sudo tee "$TARGET" >/dev/null < "$tmpfile"
rm -f "$tmpfile"

echo "Validating nginx config..."
sudo nginx -t
echo "Reloading nginx..."
sudo systemctl reload nginx
echo "Done. Wrote grouped allowlist to $TARGET"
