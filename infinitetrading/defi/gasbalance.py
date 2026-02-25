import requests
import json
import sys
import ccxt
import redis

r = redis.Redis(host='localhost', port=6379, db=0)

sys.path.append('../db/')
from pushpop import push_message

def gas_balance(address,network):
    # Define the URL based on the network parameter
    def url(network):
        if network == "mainnet" or network == "ethereum":
            return "https://api.etherscan.io/api"
        elif network == "polygon":
            return "https://api.polygonscan.com/api"
        elif network == "optimism":
            return "https://api-optimistic.etherscan.io/api"
        elif network == "arbitrum":
            return "https://api.arbiscan.io/api"
        else:
            raise ValueError("Invalid network parameter. Valid options are 'mainnet','ethereum', 'polygon', 'optimism', or 'arbitrum'.")

    api_url = url(network)

    # Construct the URL with parameters
    api_params = {
        "module": "account",
        "action": "balance",
        "address": address,
        "tag": "latest"
    }

    response = requests.get(api_url, params=api_params)

    # Check if the API call was successful
    if response.status_code != 200:
        raise ValueError(f"Error: API call failed with status code {response.status_code}")

    # Parse the JSON response
    content = json.loads(response.content)

    # Extract the gas balance
    gas = float(content["result"]) / 10**18

    # Return the gas balance
    return gas

def convert_to_slash(string):
    return string.replace('-', '/')

def get_tick(pair,exchange):
    symbol = convert_to_slash(pair)
    exchange = getattr(ccxt, exchange)()
    try:
        ticker = exchange.fetch_ticker(symbol)
        last_price = ticker['last']
        r.set(pair,last_price)
        return last_price
    except ccxt.NetworkError as e:
        print(f"Network error: {e}")
    except ccxt.ExchangeError as e:
        print(f"Exchange error: {e}")
    except Exception as e:
        print(f"Error: {e}")
    return None

#last_matic_price = get_tick(pair="ETH-USD",exchange="kraken")
#last_eth_price = get_tick(pair="MATIC-USD",exchange="kraken")
#r.set('ETH-USD',last_eth_price)
#r.set('MATIC-USD',last_matic_price)

#print(r.get('ETH-USD').decode("utf-8"))
#print(r.get('MATIC-USD').decode("utf-8"))

def calculate_dollar_value(pair, exchange_name, amount):
    last_price = get_tick(pair, exchange_name)
    if last_price is not None:
        return last_price*amount
    return None

if len(sys.argv) == 4:
    name = sys.argv[1]
    address = sys.argv[2]
    network = sys.argv[3]  
    gas = gas_balance(address,network)
    if network == "polygon":
        pair = 'MATIC-USD'
        exchange_name = 'kraken'
        dollar_value = calculate_dollar_value(pair, exchange_name, gas)
        message = f"Gas balance for address {name} ( {address} ) on the {network} network: {round(gas,2)} MATIC (${round(dollar_value, 2)})"
        print(message)
    else:
        pair = 'ETH-USD'
        exchange_name = 'kraken'
        dollar_value = calculate_dollar_value(pair, exchange_name, gas)
        message = f"Gas balance for address {name} ( {address} ) on the {network} network: {round(gas,4)} ETH (${round(dollar_value, 2)})"
        print(message)
    push_message(platform="discord",channel="#gas-tanks",message=message)
    #payload = {
    #    "text": message
    #}
    #response = requests.post(webhook_url, json=payload)
    #if response.status_code == 200:
    #    print("Message sent to Slack successfully.")
    #else:
    #    print("Failed to send message to Slack.")
