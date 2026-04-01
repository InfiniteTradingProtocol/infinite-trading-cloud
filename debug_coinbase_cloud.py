#!/usr/bin/env python3
"""
Debug script to test Coinbase Cloud API balance fetching
"""

import ccxt
import json
import sys

# Get the API credentials (you'll pass these as arguments)
if len(sys.argv) < 3:
    print("Usage: python3 debug_coinbase_cloud.py <api_key> <secret>")
    sys.exit(1)

api_key = sys.argv[1]
secret = sys.argv[2]

print("=" * 60)
print("Testing Coinbase Cloud API")
print("=" * 60)

try:
    # Initialize Coinbase exchange with Cloud API credentials
    exchange = ccxt.coinbase({
        'apiKey': api_key,
        'secret': secret,
    })
    
    print("\n1. Testing fetchAccounts()...")
    try:
        accounts = exchange.fetchAccounts()
        print(f"✅ fetchAccounts() returned {len(accounts)} accounts")
        print(f"Accounts structure: {type(accounts)}")
        
        if accounts:
            print("\nFirst account sample:")
            print(json.dumps(accounts[0], indent=2, default=str))
            
            print(f"\nAll accounts summary:")
            for i, acc in enumerate(accounts):
                currency = acc.get('currency', 'N/A')
                balance = acc.get('balance', 0)
                available = acc.get('available_balance', balance)
                print(f"  [{i}] {currency}: balance={balance}, available={available}")
    except Exception as e:
        print(f"❌ fetchAccounts() failed: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n2. Testing fetchBalance()...")
    try:
        balance = exchange.fetchBalance()
        print(f"✅ fetchBalance() successful")
        print(f"Balance structure: {type(balance)}")
        
        # Show what's in the balance
        if 'total' in balance:
            total_assets = {k: v for k, v in balance['total'].items() if v and v > 0}
            print(f"\nAssets with balance (total): {len(total_assets)}")
            for curr, amt in total_assets.items():
                print(f"  {curr}: {amt}")
        
        if 'free' in balance:
            free_assets = {k: v for k, v in balance['free'].items() if v and v > 0}
            print(f"\nAssets with balance (free): {len(free_assets)}")
            for curr, amt in free_assets.items():
                print(f"  {curr}: {amt}")
                
    except Exception as e:
        print(f"❌ fetchBalance() failed: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n3. Testing fetchTicker() for SUI/USD...")
    try:
        ticker = exchange.fetchTicker('SUI/USD')
        print(f"✅ SUI/USD ticker: ${ticker.get('last', 'N/A')}")
    except Exception as e:
        print(f"❌ fetchTicker() failed: {e}")
        
    print("\n4. Testing fetchTicker() for SUI/USDT...")
    try:
        ticker = exchange.fetchTicker('SUI/USDT')
        print(f"✅ SUI/USDT ticker: ${ticker.get('last', 'N/A')}")
    except Exception as e:
        print(f"❌ fetchTicker() failed: {e}")

except Exception as e:
    print(f"❌ Failed to initialize exchange: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 60)
print("Debug complete")
print("=" * 60)
