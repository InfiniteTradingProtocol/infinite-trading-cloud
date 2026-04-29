#!/bin/bash
# rotate_mysql_password.sh
# Rotates the MySQL richard_clare password and updates all .env files on EC2.
# Usage: ./scripts/rotate_mysql_password.sh [new_password]
# If no password is provided, a random 28-char password is generated.

set -euo pipefail

EC2="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="$HOME/.ssh/macbook.pem"
DB_USER="richard_clare"

# --- Generate or accept password ---
if [[ $# -ge 1 ]]; then
  NEW_PASS="$1"
else
  NEW_PASS=$(openssl rand -base64 21 | tr -d '=/+' | head -c 28)
fi

echo "================================================"
echo " MySQL Password Rotation — user: $DB_USER"
echo " New password: $NEW_PASS"
echo "================================================"
echo ""
echo "[1/3] Updating MySQL on EC2..."

ssh -i "$SSH_KEY" "$EC2" bash <<ENDSSH
set -e
# Use mysql_native_password so Node mysql v2 driver (no caching_sha2 support) can authenticate
sudo mysql -e "
  ALTER USER '${DB_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${NEW_PASS}';
  ALTER USER '${DB_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${NEW_PASS}';
  FLUSH PRIVILEGES;
"
echo "  MySQL password changed (both localhost and 127.0.0.1)."
ENDSSH
# (heredoc above intentionally unquoted so DB_USER/NEW_PASS expand locally)

echo ""
echo "[2/3] Updating .env files on EC2..."

# Files and the variable patterns to replace
# Format: "filepath|old_var_pattern"  (sed will match the variable name and replace its value)
ENV_FILES=(
  "/home/ubuntu/infinitetrading_api/.env|db_password"
  "/home/ubuntu/infinitetrading_api/.env|db_password_local"
  "/home/ubuntu/infinitetrading_api/.env|DB_PASSWORD_LOCAL"
  "/home/ubuntu/infinitetrading/src/.env|db_password"
  "/home/ubuntu/infinitetrading/src/.env|db_password_local"
  "/home/ubuntu/infinitetrading/src/api/.env|db_password"
  "/home/ubuntu/infinitetrading/src/db/.env|DB_PASSWORD_LOCAL"
)

ssh -i "$SSH_KEY" "$EC2" NEW_PASS="${NEW_PASS}" bash <<'ENDSSH'
set -e

update_env() {
  local file="$1"
  local var="$2"
  if grep -qiE "^${var}=" "$file" 2>/dev/null; then
    sed -i -E "s|^(${var}=)\"?[^\"]*\"?|\1\"${NEW_PASS}\"|I" "$file"
    echo "  Updated ${var} in ${file}"
  else
    echo "  SKIP: ${var} not found in ${file}"
  fi
}

update_env "/home/ubuntu/infinitetrading_api/.env"        "db_password"
update_env "/home/ubuntu/infinitetrading_api/.env"        "db_password_local"
update_env "/home/ubuntu/infinitetrading_api/.env"        "DB_PASSWORD_LOCAL"
update_env "/home/ubuntu/infinitetrading_api/express/.env" "db_password"
update_env "/home/ubuntu/infinitetrading/src/.env"        "db_password"
update_env "/home/ubuntu/infinitetrading/src/.env"        "db_password_local"
update_env "/home/ubuntu/infinitetrading/src/api/.env"    "db_password"
update_env "/home/ubuntu/infinitetrading/src/db/.env"     "DB_PASSWORD_LOCAL"
ENDSSH

echo ""
echo "[3/3] Restarting services that use the DB..."

ssh -i "$SSH_KEY" "$EC2" bash <<'ENDSSH'
set -e
pm2 restart plumber-api
pm2 restart infinitetrading-api
pm2 restart api-gateway
echo "  Services restarted."
ENDSSH

echo ""
echo "================================================"
echo " Done. Verify with:"
echo "   ssh -i $SSH_KEY $EC2 \\"
echo "     \"mysql -u ${DB_USER} -p'${NEW_PASS}' -e 'SELECT 1'\""
echo "================================================"
