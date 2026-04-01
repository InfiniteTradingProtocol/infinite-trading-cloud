#!/usr/bin/env python3
"""
Coinbase Cloud API Balance Fetcher
Bypasses CCXT library issues by using Coinbase Advanced Trade SDK directly
"""

import sys
import json
from coinbase.rest import RESTClient

def get_coinbase_cloud_balances(api_key, api_secret):
    """
    Fetch balances using Coinbase Cloud API (Advanced Trade)
    
    Args:
        api_key: Cloud API key (format: organizations/.../apiKeys/...)
        api_secret: Private key in PEM format
    
    Returns:
        dict with balances and total_usd
    """
    try:
        # Initialize Coinbase Advanced Trade client
        client = RESTClient(api_key=api_key, api_secret=api_secret)
        
        # Fetch all accounts
        accounts_response = client.get_accounts()
        
        balances = {}
        assets = []
        total_usd = 0.0
        
        if hasattr(accounts_response, 'accounts'):
            for account in accounts_response.accounts:
                currency = account.currency
                available = float(account.available_balance.value)
                total = float(account.balance.value)
                hold = total - available
                
                if total > 0:
                    # Get USD value
                    usd_value = 0.0
                    price = 0.0
                    
                    # Stablecoins are $1
                    if currency in ['USD', 'USDC', 'USDT', 'DAI', 'BUSD']:
                        price = 1.0
                        usd_value = total * price
                    else:
                        # Try to get price from product ticker
                        try:
                            product_id = f"{currency}-USD"
                            ticker = client.get_product(product_id=product_id)
                            if hasattr(ticker, 'price'):
                                price = float(ticker.price)
                                usd_value = total * price
                        except Exception as e:
                            # Price not available
                            pass
                    
                    assets.append({
                        'currency': currency,
                        'total': total,
                        'available': available,
                        'hold': hold,
                        'price_usd': price,
                        'value_usd': usd_value
                    })
                    
                    total_usd += usd_value
        
        return {
            'success': True,
            'assets': assets,
            'total_usd': total_usd,
            'count': len(assets)
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'assets': [],
            'total_usd': 0.0,
            'count': 0
        }

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(json.dumps({
            'success': False,
            'error': 'Usage: python3 coinbase_cloud_balance.py <api_key> <api_secret>'
        }))
        sys.exit(1)
    
    api_key = sys.argv[1]
    api_secret = sys.argv[2]
    
    result = get_coinbase_cloud_balances(api_key, api_secret)
    print(json.dumps(result, indent=2))
