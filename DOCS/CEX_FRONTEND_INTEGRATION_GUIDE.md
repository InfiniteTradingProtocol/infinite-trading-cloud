# CEX Frontend Integration Guide

## Overview
This guide provides instructions for integrating CEX (Centralized Exchange) trading features into the infinite-trading-frontend, following the existing patterns used for DeFi vault management.

## Current Frontend Architecture Analysis

### Managers Section Pattern
The frontend currently has a "managers" section that:
1. Displays gas wallets associated with a manager
2. Shows vault/pool information
3. Displays bot configurations
4. Shows gas balances across networks

### API Communication Pattern
The frontend communicates with:
- **Gateway API** (port 8003): `~/infinitetrading/src/api/gateway/endpoints/frontend/`
- **Main API** (port 8002): `~/infinitetrading/src/api/api.R`

#### Existing Frontend Endpoints Used:
```
GET  /getAssociatedGasWallets?apiKey=frontend&manager={address}&signature={sig}
GET  /getAllBots?manager={address}&signature={sig}
GET  /getAllGasBalance?USD=true&manager={address}&network=all&signature={sig}
POST /associateGasWallet
POST /deassociateGasWallet
```

## CEX API Endpoints Available

### 1. Register CEX Subaccount
```
POST /registerCEXSubaccount
Parameters:
  - manager: string (wallet address)
  - gas_wallet_api_key: string (from associated gas wallet)
  - payment_network: string (ethereum, polygon, optimism, arbitrum, base) - DEFAULT: "base"
  - exchange: string (coinbase, binance, okx, kucoin, bitget, etc)
  - subaccount_name: string (user-friendly name)
  - cex_api_key: string (exchange API key)
  - cex_secret: string (exchange secret or EC private key for Coinbase Cloud)
  - cex_passphrase: string (OPTIONAL - only needed for legacy Coinbase keys, okx, kucoin, bitget)
  - settings: string (optional JSON settings)
  - signature: string (wallet signature)

Notes:
  - payment_network: Network to charge $0.10 trading fees from (defaults to base for balance of low fees and ecosystem)
  - Gas wallet must have sufficient balance on the chosen payment network
  - Coinbase Cloud API Keys (organizations/.../apiKeys/...) do NOT require passphrase
  - Legacy Coinbase keys still supported but require passphrase
  - OKX, KuCoin, Bitget always require passphrase
  - Binance, Kraken, Bybit, Gate.io do NOT require passphrase

Response:
{
  status: "success",
  status_code: 200,
  message: "CEX subaccount registered successfully",
  subaccount_id: 123,
  gas_balance_usd: 45.67,
  payment_network: "base"
}
```

### 2. Get All CEX Subaccounts
```
GET /getAllCEXSubaccounts?manager={address}&signature={sig}

Response:
{
  status: "success",
  status_code: 200,
  subaccounts: [
    {
      id: 1,
      subaccount_name: "My Coinbase Bot",
      exchange: "coinbase",
      gas_wallet: "0x...",
      total_balance_usd: 1234.56,
      gas_balance_usd: 45.67,
      is_active: true,
      created_at: "2026-03-20T10:30:00Z",
      last_balance_check: "2026-03-25T02:30:00Z",
      bots: [
        {
          id: 1,
          pair: "BTC-USD",
          side: "long",
          previous_side: "neutral",
          max_usd: 500,
          share: 40,
          strategy: "ema_crossover",
          is_active: true,
          last_trade: "2026-03-24T15:00:00Z"
        }
      ]
    }
  ]
}
```

### 3. Set CEX Trading Side
```
POST /setCEXSide
Parameters:
  - gas_wallet_api_key: string
  - subaccount_name: string
  - pair: string (e.g., "BTC-USD", "ETH-USD")
  - side: string ("long", "neutral", "hold")
  - max_usd: number (maximum USD to trade)
  - share: number (percentage 0-100)
  - strategy: string (optional, "custom", "ema_crossover", etc.)

Response:
{
  status: "success",
  status_code: 200,
  message: "Side changed: neutral → long",
  bot_id: 1,
  side: "long",
  previous_side: "neutral",
  side_changed: true
}
```

### 4. Set CEX Strategy
```
POST /setCEXStrategy
Parameters:
  - gas_wallet_api_key: string
  - subaccount_name: string
  - pair: string
  - strategy: string

Response:
{
  status: "success",
  status_code: 200,
  message: "Strategy updated to 'ema_crossover'",
  bot_id: 1,
  strategy: "ema_crossover"
}
```

### 5. Delete/Deactivate CEX Bot
```
DELETE /deleteCEXBot
POST   /deactivateCEXBot
Parameters:
  - gas_wallet_api_key: string
  - subaccount_name: string
  - pair: string

Response:
{
  status: "success",
  status_code: 200,
  message: "Bot deleted successfully"
}
```

### 6. Delete CEX Subaccount
```
DELETE /deleteCEXSubaccount
Parameters:
  - manager: string
  - subaccount_name: string
  - signature: string

Response:
{
  status: "success",
  status_code: 200,
  message: "Subaccount deleted successfully (all bots removed)"
}
```

## Frontend Integration Tasks

### Phase 1: Create Gateway Endpoints (if not already created)

These should follow the same pattern as existing frontend endpoints:

#### File: `infinitetrading/src/api/gateway/endpoints/frontend/getAllCEXSubaccounts.R`
```r
getAllCEXSubaccountsHandler <- function(manager, signature = NULL) {
    tryCatch({
        url <- paste0(pep, "getAllCEXSubaccounts?",
                      "manager=", manager,
                      "&signature=", signature)
        
        response <- GET(url)
        response_content <- content(response, "text")
        parsed_response <- fromJSON(response_content)
        
        if (status_code(response) == 200) {
            if (is.character(parsed_response)) {
                parsed_response <- fromJSON(parsed_response)
            }
            return(parsed_response)
        } else {
            return(parsed_response)
        }
    }, error = function(e) {
        return(list(status = "fail", status_code = 500, 
                   message = paste("Error:", e$message)))
    })
}

pr$handle("GET", "/getAllCEXSubaccounts", getAllCEXSubaccountsHandler, 
          comment = "Fetches all CEX subaccounts for a manager")
```

### Phase 2: Frontend UI Components

#### Component Structure

```
app/
├── managers/
│   ├── page.tsx                    # Main managers page
│   ├── components/
│   │   ├── GasWalletsList.tsx      # Existing - shows DeFi gas wallets
│   │   ├── DeFiVaultsList.tsx      # Existing - shows DeFi vaults
│   │   ├── CEXSubaccountsList.tsx  # NEW - shows CEX subaccounts
│   │   ├── CEXSubaccountCard.tsx   # NEW - individual CEX subaccount card
│   │   ├── CEXBotCard.tsx          # NEW - individual CEX bot display
│   │   ├── AddCEXSubaccountModal.tsx  # NEW - register new CEX subaccount
│   │   ├── EditCEXBotModal.tsx     # NEW - edit bot parameters
│   │   └── CEXBalanceDisplay.tsx   # NEW - show CEX balances
│   └── utils/
│       ├── api.ts                  # Existing API functions
│       └── cexApi.ts               # NEW - CEX-specific API functions
```

### Phase 3: TypeScript Interfaces

#### File: `app/types/cex.ts`
```typescript
export interface CEXSubaccount {
  id: number;
  subaccount_name: string;
  exchange: 'coinbase' | 'binance' | 'okx' | 'kucoin' | 'bitget' | string;
  gas_wallet: string;
  total_balance_usd: number;
  gas_balance_usd: number;
  is_active: boolean;
  created_at: string;
  last_balance_check: string;
  bots: CEXBot[];
}

export interface CEXBot {
  id: number;
  pair: string;
  side: 'long' | 'neutral' | 'hold';
  previous_side: 'long' | 'neutral' | 'hold' | null;
  max_usd: number;
  share: number;
  strategy: string | null;
  is_active: boolean;
  last_trade: string | null;
  last_side_change: string | null;
}

export interface RegisterCEXSubaccountParams {
  manager: string;
  gas_wallet_api_key: string;
  exchange: string;
  subaccount_name: string;
  cex_api_key: string;
  cex_secret: string;
  cex_passphrase?: string;
  settings?: string;
  signature: string;
}

export interface SetCEXSideParams {
  gas_wallet_api_key: string;
  subaccount_name: string;
  pair: string;
  side: 'long' | 'neutral' | 'hold';
  max_usd: number;
  share: number;
  strategy?: string;
}
```

### Phase 4: API Functions

#### File: `app/utils/cexApi.ts`
```typescript
import { CEXSubaccount, RegisterCEXSubaccountParams, SetCEXSideParams } from '../types/cex';

const GATEWAY_API = process.env.NEXT_PUBLIC_GATEWAY_API || 'http://localhost:8003';

export async function getAllCEXSubaccounts(
  manager: string, 
  signature: string
): Promise<{ status: string; subaccounts: CEXSubaccount[] }> {
  const response = await fetch(
    `${GATEWAY_API}/getAllCEXSubaccounts?manager=${manager}&signature=${signature}`,
    { method: 'GET' }
  );
  return response.json();
}

export async function registerCEXSubaccount(
  params: RegisterCEXSubaccountParams
): Promise<{ status: string; status_code: number; message: string; subaccount_id?: number }> {
  const queryString = new URLSearchParams(params as any).toString();
  const response = await fetch(
    `${GATEWAY_API}/registerCEXSubaccount?${queryString}`,
    { method: 'POST' }
  );
  return response.json();
}

export async function setCEXSide(
  params: SetCEXSideParams
): Promise<{ status: string; status_code: number; message: string }> {
  const queryString = new URLSearchParams(params as any).toString();
  const response = await fetch(
    `${GATEWAY_API}/setCEXSide?${queryString}`,
    { method: 'POST' }
  );
  return response.json();
}

export async function deleteCEXBot(
  gas_wallet_api_key: string,
  subaccount_name: string,
  pair: string
): Promise<{ status: string; status_code: number; message: string }> {
  const response = await fetch(
    `${GATEWAY_API}/deleteCEXBot?gas_wallet_api_key=${gas_wallet_api_key}&subaccount_name=${subaccount_name}&pair=${pair}`,
    { method: 'DELETE' }
  );
  return response.json();
}

export async function deleteCEXSubaccount(
  manager: string,
  subaccount_name: string,
  signature: string
): Promise<{ status: string; status_code: number; message: string }> {
  const response = await fetch(
    `${GATEWAY_API}/deleteCEXSubaccount?manager=${manager}&subaccount_name=${subaccount_name}&signature=${signature}`,
    { method: 'DELETE' }
  );
  return response.json();
}
```

### Phase 5: UI Components

#### CEXSubaccountsList Component
```typescript
'use client';

import { useEffect, useState } from 'react';
import { CEXSubaccount } from '@/app/types/cex';
import { getAllCEXSubaccounts } from '@/app/utils/cexApi';
import CEXSubaccountCard from './CEXSubaccountCard';
import AddCEXSubaccountModal from './AddCEXSubaccountModal';

interface CEXSubaccountsListProps {
  managerAddress: string;
  signature: string;
  gasWallets: Array<{ wallet: string; api_key: string; label: string }>;
}

export default function CEXSubaccountsList({ 
  managerAddress, 
  signature,
  gasWallets 
}: CEXSubaccountsListProps) {
  const [subaccounts, setSubaccounts] = useState<CEXSubaccount[]>([]);
  const [loading, setLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);

  useEffect(() => {
    fetchSubaccounts();
  }, [managerAddress]);

  const fetchSubaccounts = async () => {
    try {
      setLoading(true);
      const result = await getAllCEXSubaccounts(managerAddress, signature);
      if (result.status === 'success') {
        setSubaccounts(result.subaccounts || []);
      }
    } catch (error) {
      console.error('Failed to fetch CEX subaccounts:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center p-8">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-purple-500"></div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <h2 className="text-2xl font-bold text-white">CEX Trading Accounts</h2>
        <button
          onClick={() => setShowAddModal(true)}
          className="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition"
        >
          + Add CEX Account
        </button>
      </div>

      {subaccounts.length === 0 ? (
        <div className="bg-gray-800/50 rounded-lg p-8 text-center">
          <p className="text-gray-400 mb-4">No CEX trading accounts configured</p>
          <button
            onClick={() => setShowAddModal(true)}
            className="px-6 py-3 bg-purple-600 hover:bg-purple-700 text-white rounded-lg transition"
          >
            Connect Your First Exchange
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {subaccounts.map((subaccount) => (
            <CEXSubaccountCard 
              key={subaccount.id} 
              subaccount={subaccount}
              onUpdate={fetchSubaccounts}
              managerAddress={managerAddress}
              signature={signature}
            />
          ))}
        </div>
      )}

      {showAddModal && (
        <AddCEXSubaccountModal
          managerAddress={managerAddress}
          signature={signature}
          gasWallets={gasWallets}
          onClose={() => setShowAddModal(false)}
          onSuccess={() => {
            setShowAddModal(false);
            fetchSubaccounts();
          }}
        />
      )}
    </div>
  );
}
```

#### CEXSubaccountCard Component
```typescript
'use client';

import { useState } from 'react';
import { CEXSubaccount } from '@/app/types/cex';
import { deleteCEXSubaccount } from '@/app/utils/cexApi';
import CEXBotCard from './CEXBotCard';
import AddCEXBotModal from './AddCEXBotModal';

interface CEXSubaccountCardProps {
  subaccount: CEXSubaccount;
  onUpdate: () => void;
  managerAddress: string;
  signature: string;
}

export default function CEXSubaccountCard({ 
  subaccount, 
  onUpdate,
  managerAddress,
  signature 
}: CEXSubaccountCardProps) {
  const [showAddBotModal, setShowAddBotModal] = useState(false);
  const [deleting, setDeleting] = useState(false);

  const handleDelete = async () => {
    if (!confirm(`Delete ${subaccount.subaccount_name}? This will remove all bots.`)) {
      return;
    }

    try {
      setDeleting(true);
      const result = await deleteCEXSubaccount(
        managerAddress,
        subaccount.subaccount_name,
        signature
      );
      
      if (result.status === 'success') {
        onUpdate();
      } else {
        alert(`Failed: ${result.message}`);
      }
    } catch (error) {
      console.error('Delete failed:', error);
      alert('Failed to delete subaccount');
    } finally {
      setDeleting(false);
    }
  };

  const exchangeLogos: Record<string, string> = {
    coinbase: '🟦',
    binance: '🟡',
    okx: '⬛',
    kucoin: '🟢',
    bitget: '🔷'
  };

  return (
    <div className="bg-gray-800/50 rounded-lg p-6 border border-gray-700 hover:border-purple-500 transition">
      <div className="flex justify-between items-start mb-4">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-2xl">{exchangeLogos[subaccount.exchange] || '📊'}</span>
            <h3 className="text-xl font-bold text-white">{subaccount.subaccount_name}</h3>
          </div>
          <p className="text-sm text-gray-400 capitalize">{subaccount.exchange}</p>
        </div>
        <div className="flex gap-2">
          <span className={`px-2 py-1 rounded text-xs ${subaccount.is_active ? 'bg-green-500/20 text-green-400' : 'bg-red-500/20 text-red-400'}`}>
            {subaccount.is_active ? 'Active' : 'Inactive'}
          </span>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div className="bg-gray-900/50 rounded p-3">
          <p className="text-xs text-gray-400 mb-1">Exchange Balance</p>
          <p className="text-lg font-semibold text-white">${subaccount.total_balance_usd.toFixed(2)}</p>
        </div>
        <div className="bg-gray-900/50 rounded p-3">
          <p className="text-xs text-gray-400 mb-1">Gas Balance</p>
          <p className="text-lg font-semibold text-white">${subaccount.gas_balance_usd.toFixed(2)}</p>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex justify-between items-center">
          <h4 className="text-sm font-semibold text-gray-300">Trading Bots ({subaccount.bots.length})</h4>
          <button
            onClick={() => setShowAddBotModal(true)}
            className="text-xs px-3 py-1 bg-purple-600/50 hover:bg-purple-600 text-white rounded transition"
          >
            + Add Bot
          </button>
        </div>

        {subaccount.bots.length === 0 ? (
          <p className="text-sm text-gray-500 italic">No bots configured</p>
        ) : (
          <div className="space-y-2">
            {subaccount.bots.map((bot) => (
              <CEXBotCard 
                key={bot.id} 
                bot={bot} 
                subaccount={subaccount}
                onUpdate={onUpdate}
              />
            ))}
          </div>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-gray-700 flex justify-between">
        <p className="text-xs text-gray-500">Gas Wallet: {subaccount.gas_wallet.substring(0, 10)}...</p>
        <button
          onClick={handleDelete}
          disabled={deleting}
          className="text-xs text-red-400 hover:text-red-300 disabled:opacity-50"
        >
          {deleting ? 'Deleting...' : 'Delete Account'}
        </button>
      </div>

      {showAddBotModal && (
        <AddCEXBotModal
          subaccount={subaccount}
          onClose={() => setShowAddBotModal(false)}
          onSuccess={() => {
            setShowAddBotModal(false);
            onUpdate();
          }}
        />
      )}
    </div>
  );
}
```

### Phase 6: Integration with Existing Managers Page

Modify the main managers page to include CEX subaccounts section:

```typescript
// app/managers/page.tsx

import { useEffect, useState } from 'react';
import GasWalletsList from './components/GasWalletsList';
import DeFiVaultsList from './components/DeFiVaultsList';
import CEXSubaccountsList from './components/CEXSubaccountsList'; // NEW

export default function ManagersPage() {
  const [managerAddress, setManagerAddress] = useState('');
  const [signature, setSignature] = useState('');
  const [gasWallets, setGasWallets] = useState([]);
  const [activeTab, setActiveTab] = useState<'defi' | 'cex'>('defi'); // NEW

  // ... existing code for wallet connection and signature ...

  return (
    <div className="container mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold text-white mb-8">Trading Manager Dashboard</h1>

      {/* Tab Navigation */}
      <div className="flex gap-4 mb-6 border-b border-gray-700">
        <button
          onClick={() => setActiveTab('defi')}
          className={`px-6 py-3 font-semibold transition ${
            activeTab === 'defi'
              ? 'text-purple-400 border-b-2 border-purple-400'
              : 'text-gray-400 hover:text-gray-300'
          }`}
        >
          DeFi Vaults
        </button>
        <button
          onClick={() => setActiveTab('cex')}
          className={`px-6 py-3 font-semibold transition ${
            activeTab === 'cex'
              ? 'text-purple-400 border-b-2 border-purple-400'
              : 'text-gray-400 hover:text-gray-300'
          }`}
        >
          CEX Trading
        </button>
      </div>

      {/* Gas Wallets - Show on both tabs */}
      <div className="mb-8">
        <GasWalletsList 
          managerAddress={managerAddress}
          signature={signature}
          onWalletsUpdate={setGasWallets}
        />
      </div>

      {/* Content based on active tab */}
      {activeTab === 'defi' && (
        <DeFiVaultsList
          managerAddress={managerAddress}
          signature={signature}
          gasWallets={gasWallets}
        />
      )}

      {activeTab === 'cex' && (
        <CEXSubaccountsList
          managerAddress={managerAddress}
          signature={signature}
          gasWallets={gasWallets}
        />
      )}
    </div>
  );
}
```

## Security Considerations

1. **Signature Verification**: All CEX endpoints require wallet signature verification
2. **API Key Encryption**: CEX credentials are encrypted using AES-256-CBC
3. **Gas Wallet Association**: CEX subaccounts must be linked to an associated gas wallet
4. **Minimum Gas Balance**: $10 minimum gas balance required for CEX operations

## Testing Checklist

- [ ] Register new CEX subaccount with valid credentials
- [ ] View all CEX subaccounts for a manager
- [ ] Create new trading bot on a subaccount
- [ ] Update bot side (long/neutral/hold)
- [ ] Update bot strategy
- [ ] Delete individual bot
- [ ] Delete entire subaccount (cascade delete bots)
- [ ] Verify gas balance checking
- [ ] Test with multiple exchanges (Coinbase, Binance, OKX, etc.)
- [ ] Verify signature validation
- [ ] Test error handling for insufficient gas
- [ ] Test error handling for invalid credentials

## Environment Variables

Add to `.env.local`:
```bash
NEXT_PUBLIC_GATEWAY_API=http://localhost:8003
NEXT_PUBLIC_MAIN_API=http://localhost:8002
```

For production:
```bash
NEXT_PUBLIC_GATEWAY_API=https://api.infinitetrading.io/gateway
NEXT_PUBLIC_MAIN_API=https://api.infinitetrading.io
```

## Database Schema Reference

The backend uses these tables:
- `cex_subaccounts` - Stores exchange accounts
- `cex_bots` - Stores trading bot configurations
- `cex_trades` - Stores trade history
- `cex_strategies` - Stores available strategies
- `associated_gas_wallets` - Links gas wallets to managers

## Next Steps

1. Create gateway endpoint files if they don't exist
2. Add TypeScript interfaces
3. Create API utility functions
4. Build UI components following existing design system
5. Integrate into managers page with tab navigation
6. Add comprehensive error handling and loading states
7. Test thoroughly with real exchange credentials
8. Deploy to staging for QA

## Support Exchanges

Currently supported:
- **Coinbase** (Cloud API Keys recommended - no passphrase; legacy keys supported - requires passphrase)
- **Binance** (no passphrase)
- **OKX** (requires passphrase)
- **KuCoin** (requires passphrase)
- **Bitget** (requires passphrase)
- **Kraken** (no passphrase)
- **Bybit** (no passphrase)
- **Gate.io** (no passphrase)

### Coinbase API Key Types

#### Cloud API Keys (Recommended) ⭐
- **Format**: `organizations/{org-id}/apiKeys/{key-id}`
- **Example**: `organizations/495a1191-4d9b-4fba-ba93-b014ee359a5b/apiKeys/e12e74a7-f972-4ead-a7a4-33c0d6b71494`
- **Secret**: EC Private Key in PEM format (multi-line with `\n`)
- **Passphrase**: NOT required ❌
- **Security**: More secure with EC cryptography
- **Creation**: https://portal.cdp.coinbase.com/

Example Cloud API Secret (PEM format):
```
-----BEGIN EC PRIVATE KEY-----\nMHcCAQEEIKMwetfSprMthcUSFJhc5Vgth2miVRzEaVIg3raQqJBWoAoGCCqGSM49\nAwEHoUQDQgAEijjQLOiVpXN/Jl82Xt66Yr/kfKioQTP60xNOe2WQOCyZTI2S8OXw\nmgM1zeKA7B8haoy0zxvbHoaW+8bTy4k+TA==\n-----END EC PRIVATE KEY-----\n
```

#### Legacy API Keys (Still Supported)
- **Format**: Short alphanumeric string
- **Secret**: Standard API secret
- **Passphrase**: REQUIRED ✅
- **Creation**: Coinbase Pro/Advanced Trade settings (may be deprecated)

### Frontend Implementation: Dynamic Passphrase Field

The frontend should detect Cloud API Keys and hide/show the passphrase field:

```typescript
// In AddCEXSubaccountModal component
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

// Determine if passphrase is needed
const needsPassphrase = ['okx', 'kucoin', 'bitget'].includes(formData.exchange) ||
                        (formData.exchange === 'coinbase' && !isCloudAPIKey);

// In JSX:
<div className="space-y-4">
  {/* API Key */}
  <div>
    <label className="block text-sm font-medium text-gray-300 mb-2">
      API Key *
    </label>
    <input
      type="text"
      value={formData.cex_api_key}
      onChange={(e) => setFormData({...formData, cex_api_key: e.target.value})}
      className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white"
      placeholder={formData.exchange === 'coinbase' ? 'organizations/.../apiKeys/...' : 'API Key'}
      required
    />
    {formData.exchange === 'coinbase' && (
      <div className="mt-2 text-xs text-gray-400">
        {isCloudAPIKey ? (
          <div className="flex items-center gap-2 text-green-400">
            <span>✅</span>
            <span>Cloud API Key detected (no passphrase needed)</span>
          </div>
        ) : formData.cex_api_key ? (
          <div className="flex items-center gap-2 text-yellow-400">
            <span>⚠️</span>
            <span>Legacy key detected (passphrase required)</span>
          </div>
        ) : (
          <span>Enter your Coinbase API key</span>
        )}
      </div>
    )}
  </div>

  {/* Secret */}
  <div>
    <label className="block text-sm font-medium text-gray-300 mb-2">
      Secret / Private Key *
    </label>
    <textarea
      value={formData.cex_secret}
      onChange={(e) => setFormData({...formData, cex_secret: e.target.value})}
      className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white font-mono text-xs"
      rows={isCloudAPIKey ? 6 : 2}
      placeholder={isCloudAPIKey ? '-----BEGIN EC PRIVATE KEY-----\n...' : 'API Secret'}
      required
    />
    {isCloudAPIKey && (
      <p className="mt-1 text-xs text-gray-400">
        Paste the entire EC private key including BEGIN/END lines
      </p>
    )}
  </div>

  {/* Passphrase - Conditional */}
  {needsPassphrase && (
    <div>
      <label className="block text-sm font-medium text-gray-300 mb-2">
        Passphrase *
      </label>
      <input
        type="password"
        value={formData.cex_passphrase}
        onChange={(e) => setFormData({...formData, cex_passphrase: e.target.value})}
        className="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white"
        placeholder="API Passphrase"
        required
      />
    </div>
  )}
  
  {/* Help text for Coinbase Cloud Keys */}
  {formData.exchange === 'coinbase' && !needsPassphrase && formData.cex_api_key && (
    <div className="p-3 bg-blue-500/10 border border-blue-500/30 rounded-lg">
      <p className="text-sm text-blue-300">
        ℹ️ <strong>Coinbase Cloud API Keys</strong> use EC cryptography and don't require a passphrase.
        Make sure to securely store your private key - it cannot be recovered if lost.
      </p>
    </div>
  )}
</div>
```

Each exchange has different authentication requirements checked in the backend.
