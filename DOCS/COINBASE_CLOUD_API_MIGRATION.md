# Coinbase Advanced Trade API (Cloud API Keys) Migration Guide

## Overview
Coinbase has transitioned from legacy API keys (with passphrases) to Cloud API Keys which use:
- OAuth 2.0 style key format: `organizations/{org-id}/apiKeys/{key-id}`
- EC Private Key (PEM format) instead of secret + passphrase
- JWT-based authentication

## Key Format Examples

### API Key (organizations/apiKeys format)
```
organizations/495a1191-4d9b-4fba-ba93-b014ee359a5b/apiKeys/e12e74a7-f972-4ead-a7a4-33c0d6b71494
```

### Private Key (EC PEM format with \n)
```
-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIKMwetfSprMthcUSFJhc5Vgth2miVRzEaVIg3raQqJBWoAoGCCqGSM49\nAwEHoUQDQgAEijjQLOiVpXN/Jl82Xt66Yr/kfKioQTP60xNOe2WQOCyZTI2S8OXw\nmgM1zeKA7B8haoy0zxvbHoaW+8bTy4k+TA==\n-----END EC PRIVATE KEY-----\n
```

## Changes Required

### 1. Database Schema - NO CHANGES NEEDED ✅
The current schema already supports this:
- `cex_api_key_encrypted TEXT` - Can store long org/apiKeys format
- `cex_secret_encrypted TEXT` - Can store multi-line PEM keys
- `cex_passphrase_encrypted TEXT` - Optional (NULL for Coinbase Cloud keys)

### 2. Detection Logic
We need to distinguish between:
- **Legacy Coinbase Keys**: Short API key + secret + passphrase
- **Cloud API Keys**: Long org/apiKeys format + EC private key + NO passphrase

### 3. CCXT Initialization Changes

#### Current Code (cex_tradebot.R):
```r
if (exchange_name %in% c("coinbase", "okx", "kucoin", "bitget")) {
    # Needs passphrase
    if (is.null(credentials$passphrase)) {
        cat(sprintf("  ⚠️ Exchange %s requires passphrase but none provided\n", exchange_name))
        return(NULL)
    }
    py_string <- sprintf(
        "%s = ccxt.%s({
            'apiKey': '%s',
            'secret': '%s',
            'password': '%s',
            'enableRateLimit': True
        })",
        ccxt_exchange, ccxt_exchange,
        credentials$key,
        credentials$secret,
        credentials$passphrase
    )
}
```

#### Updated Code:
```r
# Detect Coinbase Cloud API Key (organizations/apiKeys format)
is_coinbase_cloud <- exchange_name == "coinbase" && 
                     grepl("^organizations/.*/apiKeys/", credentials$key)

if (is_coinbase_cloud) {
    # Coinbase Cloud API Keys (no passphrase, uses EC private key)
    py_string <- sprintf(
        "%s = ccxt.coinbase({
            'apiKey': '%s',
            'secret': '%s',
            'enableRateLimit': True
        })",
        ccxt_exchange,
        credentials$key,
        credentials$secret  # This is the EC private key
    )
} else if (exchange_name %in% c("coinbase", "okx", "kucoin", "bitget")) {
    # Legacy keys or other exchanges that need passphrase
    if (is.null(credentials$passphrase)) {
        cat(sprintf("  ⚠️ Exchange %s requires passphrase but none provided\n", exchange_name))
        return(NULL)
    }
    py_string <- sprintf(
        "%s = ccxt.%s({
            'apiKey': '%s',
            'secret': '%s',
            'password': '%s',
            'enableRateLimit': True
        })",
        ccxt_exchange, ccxt_exchange,
        credentials$key,
        credentials$secret,
        credentials$passphrase
    )
}
```

### 4. Frontend Validation Changes

Update the registration form to:
1. Detect Cloud API Key format
2. Make passphrase optional for Coinbase
3. Show different help text based on key type

#### AddCEXSubaccountModal.tsx changes:
```typescript
const [formData, setFormData] = useState({
  exchange: 'coinbase',
  subaccount_name: '',
  cex_api_key: '',
  cex_secret: '',
  cex_passphrase: '',
  gas_wallet_api_key: ''
});

// Detect Coinbase Cloud API Key
const isCloudAPIKey = formData.exchange === 'coinbase' && 
                      formData.cex_api_key.startsWith('organizations/');

// Validate passphrase requirement
const needsPassphrase = ['okx', 'kucoin', 'bitget'].includes(formData.exchange) ||
                        (formData.exchange === 'coinbase' && !isCloudAPIKey);

// In the form JSX:
{needsPassphrase ? (
  <div>
    <label>Passphrase {needsPassphrase && '*'}</label>
    <input
      type="password"
      value={formData.cex_passphrase}
      onChange={(e) => setFormData({...formData, cex_passphrase: e.target.value})}
      required={needsPassphrase}
    />
  </div>
) : (
  <p className="text-sm text-gray-400">
    ℹ️ Cloud API Keys don't require a passphrase
  </p>
)}

// Help text based on key type
{formData.exchange === 'coinbase' && (
  <div className="text-xs text-gray-400 mt-2">
    {isCloudAPIKey ? (
      <>
        <p>✅ Cloud API Key detected</p>
        <p>Format: organizations/[org-id]/apiKeys/[key-id]</p>
        <p>Secret: Paste the entire EC PRIVATE KEY (including BEGIN/END lines)</p>
      </>
    ) : (
      <>
        <p>Legacy API Key format detected</p>
        <p>Passphrase is required for legacy keys</p>
      </>
    )}
  </div>
)}
```

### 5. Backend Validation Changes

#### registerCEXSubaccount handler update:
```r
# Detect Coinbase Cloud API Key
is_coinbase_cloud <- exchange == "coinbase" && 
                     grepl("^organizations/.*/apiKeys/", cex_api_key)

# Validate passphrase requirement
passphrase_required <- exchange %in% c("okx", "kucoin", "bitget") ||
                       (exchange == "coinbase" && !is_coinbase_cloud)

if (passphrase_required && (is.null(cex_passphrase) || cex_passphrase == "")) {
    return(list(status = "fail", status_code = 400, 
               message = sprintf("%s requires a passphrase (legacy API keys)", exchange)))
}

# Validate Cloud API Key format
if (is_coinbase_cloud) {
    if (!grepl("BEGIN EC PRIVATE KEY", cex_secret)) {
        return(list(status = "fail", status_code = 400,
                   message = "Invalid EC private key format. Must be PEM format with BEGIN/END markers"))
    }
}
```

### 6. Documentation Updates

Update error messages and docs to explain:
- Coinbase now supports two types of API keys
- Cloud API Keys are recommended (more secure, easier to manage)
- Legacy keys still work but may be deprecated
- How to create Cloud API Keys in Coinbase Advanced Trade

### 7. Migration Path for Existing Users

Users with legacy Coinbase API keys can:
1. Keep using them (backend supports both)
2. Migrate to Cloud API Keys:
   - Create new Cloud API Key in Coinbase
   - Delete old subaccount in frontend
   - Register new subaccount with Cloud API Key
   - Recreate bots with same settings

## Testing Checklist

- [ ] Register Coinbase subaccount with Cloud API Key (no passphrase)
- [ ] Register Coinbase subaccount with legacy key (with passphrase) 
- [ ] Verify both types work in cex_tradebot.R
- [ ] Test with EC private key containing \n characters
- [ ] Test with very long organization/apiKeys format
- [ ] Verify encryption/decryption works for multi-line keys
- [ ] Test OKX/KuCoin/Bitget still require passphrase
- [ ] Verify error messages are clear

## CCXT Version Requirements

Ensure CCXT >= 4.0.0 for proper Cloud API Key support:
```bash
pip install --upgrade ccxt
# or
pip install 'ccxt>=4.0.0'
```

## API Key Creation Guide (for users)

### Coinbase Cloud API Keys (Recommended):
1. Go to https://portal.cdp.coinbase.com/
2. Click "API Keys" → "Create API Key"
3. Select permissions: "View" and "Trade"
4. Copy the API Key Name (organizations/xxx/apiKeys/xxx format)
5. Download the EC private key file (keep it secure!)
6. Paste entire private key including BEGIN/END lines

### Legacy API Keys:
1. Go to Coinbase Pro/Advanced Trade settings
2. Create API key with trade permissions
3. Note: These may be deprecated in the future

## Security Notes

⚠️ **EC Private Keys are extremely sensitive**:
- Never expose them in logs
- Store encrypted in database (already done)
- Users should download and securely store backup
- Keys can be rotated without changing subaccount configuration

✅ **Advantages of Cloud API Keys**:
- No passphrase to remember
- Better security with EC cryptography
- Easier to rotate/revoke
- Scoped permissions
- Organization-level management
