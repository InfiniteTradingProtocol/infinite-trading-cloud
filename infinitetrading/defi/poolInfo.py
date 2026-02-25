from gql import gql, Client
from gql.transport.aiohttp import AIOHTTPTransport

def fetch_pool_info(pool_address):
    # Configure the GraphQL client
    transport = AIOHTTPTransport(url="https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3")
    client = Client(transport=transport, fetch_schema_from_transport=True)
    
    # Define the GraphQL query to fetch the pool info
    query = gql('''
        query PoolInfo($poolAddress: ID!) {
            pool(id: $poolAddress) {
                id
                token0 {
                    id
                    symbol
                }
                token1 {
                    id
                    symbol
                }
                feeTier
                sqrtPrice
                liquidity
                tick
                feeGrowthGlobal0X128
                feeGrowthGlobal1X128
            }
        }
    ''')
    
    # Execute the GraphQL query with the pool address as a variable
    result = client.execute(query, variable_values={'poolAddress': pool_address})
    
    # Extract and return the relevant pool information
    pool_info = result['pool']
        # Convert numerical values to readable numbers
    token0_id = pool_info['token0']['id']
    token0_symbol = pool_info['token0']['symbol']
    token1_id = pool_info['token1']['id']
    token1_symbol = pool_info['token1']['symbol']
    liquidity = float(pool_info['liquidity'])
    sqrt_price = float(pool_info['sqrtPrice'])
    fee_growth_global0 = float(pool_info['feeGrowthGlobal0X128'])
    fee_growth_global1 = float(pool_info['feeGrowthGlobal1X128'])

    if token0_id == '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48':
        liquidity /= 10**6  # USDC has 6 decimals
    elif token0_id == '0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2':
        liquidity /= 10**8  # WBTC has 8 decimals
    else:
        liquidity /= 10**18  # Other tokens have 18 decimals

    sqrt_price /= 1e18  # Convert sqrt price to decimal representation
    fee_growth_global0 /= 1e18  # Convert fee growth to decimal representation
    fee_growth_global1 /= 1e18  # Convert fee growth to decimal representation

    # Print the converted pool information
    print("Pool ID:", pool_info['id'])
    print("Token 0 ID:", pool_info['token0']['id'])
    print("Token 0 Symbol:", pool_info['token0']['symbol'])
    print("Token 1 ID:", pool_info['token1']['id'])
    print("Token 1 Symbol:", pool_info['token1']['symbol'])
    fee = float(pool_info['feeTier'])/10000
    formatted_fee = f"{fee}%"
    print("Fee Tier:", formatted_fee)
    print("Square Root Price:", sqrt_price)
    print("Liquidity:", liquidity)
    print("Tick:", pool_info['tick'])
    print("Fee Growth Global 0:", fee_growth_global0)
    print("Fee Growth Global 1:", fee_growth_global1)
    return pool_info

def estimate_price_impact(pool_address, trade_amount):
    # Fetch the pool information using the pool address
    pool_info = fetch_pool_info(pool_address)
    
    # Get the current reserve amounts and tick position of the pool
    reserve0 = float(pool_info['token0']['reserve'])
    reserve1 = float(pool_info['token1']['reserve'])
    tick = int(pool_info['tick'])
    
    # Calculate the mid price of the pool
    mid_price = reserve1 / reserve0
    
    # Calculate the virtual reserves after the trade
    new_reserve0 = reserve0 + trade_amount
    new_reserve1 = reserve1 - (trade_amount * mid_price)
    
    # Calculate the new mid price after the trade
    new_mid_price = new_reserve1 / new_reserve0
    
    # Calculate the price impact as a percentage
    price_impact = abs((new_mid_price - mid_price) / mid_price) * 100
    
    return price_impact

address = "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640"
print(fetch_pool_info(address))
estimate_price_impact(address,trade_amount = 10)

