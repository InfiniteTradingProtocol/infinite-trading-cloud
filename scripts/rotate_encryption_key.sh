#!/bin/bash
# rotate_encryption_key.sh
#
# Generates a new AES-256-CBC encryption key, re-encrypts all private keys
# stored in api_tokens.encrypted_pk, and updates all .env files on EC2.
#
# Usage: ./scripts/rotate_encryption_key.sh [new_key_base64]
#   If no key is provided, a new random 32-byte key (base64) is generated.
#
# IMPORTANT: Services are briefly stopped during re-encryption to prevent
# any transactions reading/writing with a stale key.

set -euo pipefail

EC2="ubuntu@ec2-3-135-99-211.us-east-2.compute.amazonaws.com"
SSH_KEY="$HOME/.ssh/macmini.pem"

# ── 1. Get old key from EC2 ──────────────────────────────────────────────────
echo "[1/5] Reading current encryption key from EC2..."
OLD_KEY=$(ssh -i "$SSH_KEY" "$EC2" \
  "grep 'encryption_key' /home/ubuntu/infinitetrading_api/express/.env | head -1 | sed 's/.*=\"\\(.*\\)\"/\\1/'")
echo "  Old key: ${OLD_KEY:0:10}... (truncated)"

# ── 2. Generate new key ───────────────────────────────────────────────────────
if [[ $# -ge 1 ]]; then
  NEW_KEY="$1"
else
  NEW_KEY=$(openssl rand -base64 32)
fi
echo ""
echo "[2/5] New encryption key: ${NEW_KEY:0:10}... (truncated)"
echo ""
echo "======================================================"
echo " ABOUT TO RE-ENCRYPT ALL PRIVATE KEYS IN api_tokens"
echo "  Old key: $OLD_KEY"
echo "  New key: $NEW_KEY"
echo "======================================================"
echo ""
read -p "Proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# ── 3. Stop services (prevent stale-key reads during rotation) ───────────────
echo ""
echo "[3/5] Stopping services..."
ssh -i "$SSH_KEY" "$EC2" "pm2 stop plumber-api infinitetrading-api api-gateway && echo '  Services stopped.'"

# ── 4. Re-encrypt all rows on EC2 using Node.js ──────────────────────────────
echo ""
echo "[4/5] Re-encrypting api_tokens on EC2..."

ssh -i "$SSH_KEY" "$EC2" OLD_KEY="$OLD_KEY" NEW_KEY="$NEW_KEY" node << 'NODESCRIPT'
const crypto = require('crypto');
const mysql  = require('/home/ubuntu/infinitetrading_api/express/node_modules/mysql');

const oldKey = Buffer.from(process.env.OLD_KEY, 'base64');
const newKey = Buffer.from(process.env.NEW_KEY, 'base64');

if (oldKey.length !== 32) { console.error('OLD_KEY must be 32 bytes (base64 encoded)'); process.exit(1); }
if (newKey.length !== 32) { console.error('NEW_KEY must be 32 bytes (base64 encoded)'); process.exit(1); }

function decrypt(hexData, key) {
  const buf = Buffer.from(hexData, 'hex');
  const iv  = buf.slice(0, 16);
  const ct  = buf.slice(16);
  const d   = crypto.createDecipheriv('aes-256-cbc', key, iv);
  d.setAutoPadding(true);
  return Buffer.concat([d.update(ct), d.final()]).toString('hex');
}

function encrypt(hexData, key) {
  const iv        = crypto.randomBytes(16);
  const plaintext = Buffer.from(hexData, 'hex');
  const c         = crypto.createCipheriv('aes-256-cbc', key, iv);
  const encrypted = Buffer.concat([c.update(plaintext), c.final()]);
  return Buffer.concat([iv, encrypted]).toString('hex');
}

// Get DB password from .env
const fs  = require('fs');
const env = fs.readFileSync('/home/ubuntu/infinitetrading_api/express/.env', 'utf8');
const pw  = (env.match(/^db_password="([^"]+)"/m) || [])[1];
const host= (env.match(/^db_host="([^"]+)"/m) || [])[1] || 'localhost';

const pool = mysql.createPool({
  host: host, user: 'richard_clare', password: pw,
  database: 'infinitetrading', connectionLimit: 2,
});

function query(sql, params) {
  return new Promise((res, rej) =>
    pool.query(sql, params, (err, rows) => err ? rej(err) : res(rows)));
}

(async () => {
  try {
    const rows = await query('SELECT token, encrypted_pk FROM api_tokens', []);
    console.log(`  Found ${rows.length} tokens to re-encrypt.`);

    let ok = 0, fail = 0;
    for (const row of rows) {
      try {
        const plainHex    = decrypt(row.encrypted_pk, oldKey);
        const reEncrypted = encrypt(plainHex, newKey);
        await query('UPDATE api_tokens SET encrypted_pk = ? WHERE token = ?',
                    [reEncrypted, row.token]);
        console.log(`  ✅ Re-encrypted token ${row.token}`);
        ok++;
      } catch (e) {
        console.error(`  ❌ FAILED token ${row.token}: ${e.message}`);
        fail++;
      }
    }

    if (fail > 0) {
      console.error(`\n  FATAL: ${fail} tokens failed to re-encrypt.`);
      console.error('  The old key is still in .env files — investigate before restarting.');
      pool.end();
      process.exit(1);
    }

    console.log(`\n  Done. ${ok}/${rows.length} tokens re-encrypted successfully.`);
    pool.end();
  } catch (e) {
    console.error('  DB error:', e.message);
    pool.end();
    process.exit(1);
  }
})();
NODESCRIPT

REENCRYPT_STATUS=$?
if [[ $REENCRYPT_STATUS -ne 0 ]]; then
  echo ""
  echo "ERROR: Re-encryption failed. Restarting services with OLD key still in .env."
  ssh -i "$SSH_KEY" "$EC2" "pm2 start plumber-api infinitetrading-api api-gateway"
  exit 1
fi

# ── 5. Update .env files on EC2 ───────────────────────────────────────────────
echo ""
echo "[5/5] Updating .env files on EC2 with new key..."

ssh -i "$SSH_KEY" "$EC2" NEW_KEY="$NEW_KEY" bash << 'ENDSSH'
set -e
update_key() {
  local file="$1"
  if [[ -f "$file" ]] && grep -q 'encryption_key' "$file"; then
    sed -i -E "s|^(encryption_key=)\"[^\"]*\"|\1\"${NEW_KEY}\"|" "$file"
    echo "  Updated: $file"
  else
    echo "  SKIP (not found): $file"
  fi
}
update_key "/home/ubuntu/infinitetrading/src/api/.env"
update_key "/home/ubuntu/infinitetrading_api/express/.env"
ENDSSH

# Update local .env too
LOCAL_ENV="/Users/richardclare/infinite-trading-cloud/infinitetrading_api/express/.env"
if grep -q 'encryption_key' "$LOCAL_ENV" 2>/dev/null; then
  sed -i '' -E "s|^(encryption_key=)\"[^\"]*\"|\1\"${NEW_KEY}\"|" "$LOCAL_ENV"
  echo "  Updated local: $LOCAL_ENV"
fi

# ── 6. Restart services ───────────────────────────────────────────────────────
echo ""
echo "[6/6] Restarting services with new key..."
ssh -i "$SSH_KEY" "$EC2" "pm2 start plumber-api infinitetrading-api api-gateway --update-env && echo '  Services started.'"

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "======================================================"
echo " Rotation complete!"
echo "  New key: $NEW_KEY"
echo "  Verify with: curl -s http://localhost:8000/getWallet?apiKey=<any-token>"
echo "======================================================"
