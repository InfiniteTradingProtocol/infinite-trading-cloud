import os
from dotenv import load_dotenv
from web3 import Web3
from web3.utils.address import to_checksum_address
# Load environment variables from .env file
load_dotenv()

# Retrieve the Infura API key from the environment variables
infura_api_key = os.getenv('INFURA_API_KEY')

def uniswapv3_fees(pool,network): 
    pool = pool.upper()
    if network == 'ethereum' or network == 'mainnet':
        provider_url = os.getenv('ETHEREUM_PROVIDER_URL')
    elif network == 'polygon':
        provider_url = os.getenv('POLYGON_PROVIDER_URL')
    elif network == 'arbitrum':
        provider_url = os.getenv('ARBITRUM_PROVIDER_URL')
    elif network == 'optimism':
        provider_url = os.getenv('OPTIMISM_PROVIDER_URL')
    else:
        raise ValueError("Invalid network")
    # Connect to Ethereum network using the provider URL
    provider = Web3.HTTPProvider(provider_url)
    web3 = Web3(provider)

    # Define Uniswap V3 pool contract address and ABI
    contract_abi = [{"constant":True,"inputs":[],"name":"feeTier","outputs":[{"internalType":"uint24","name":"","type":"uint24"}],"payable":False,"stateMutability":"view","type":"function"}]

    # Retrieve Uniswap V3 pool contract
    pool_contract = web3.eth.contract(address=to_checksum_address(pool), abi=contract_abi)

    # Fetch fee tier from the pool contract
    fee_tier = pool_contract.functions.feeTier().call()

    # Convert fee tier to fee percentage
    fee_percentage = fee_tier / 1e6

    # Print the fee percentage
    print("Uniswap V3 fee percentage:", fee_percentage)
    return(fee_percentage)


uniswapv3_fees(pool="0x45dda9cb7c25131df268515131f647d726f50608",network="polygon")
