from defi import *
import time
from math import ceil
from math import floor

def discord(msg,channel="#pools-trading"):
    send_message(message=msg,channel=channel,platform="discord")
    
def index(portfolio_balances, portfolio_prices, target_weights,verbose=False):
    if len(portfolio_balances) != len(portfolio_prices) or len(portfolio_balances) != len(target_weights):
        raise ValueError("Input lists must have the same length")
    total_portfolio_value = sum([balance * price for balance, price in zip(portfolio_balances, portfolio_prices)])
    current_allocation = [(balance * price) / total_portfolio_value for balance, price in zip(portfolio_balances, portfolio_prices)]
    target_allocation = [weight / sum(target_weights) for weight in target_weights]
    allocation_difference = [target - current for target, current in zip(target_allocation, current_allocation)]
    trade_amounts = [(diff * total_portfolio_value) / price for diff, price in zip(allocation_difference, portfolio_prices)]
    results = {'current_allocation': current_allocation,'target_allocation': target_allocation,'trade_amounts': trade_amounts}
    if verbose:
        print("Portfolio Balances: ",portfolio_balances)
        print("Assets Prices: ", portfolio_prices)
        print("Actual Allocation: ", current_allocation)
        print("Desired Allocation: ", target_allocation)
        print("Trades required to achive desired allocations: ", trade_amounts)
    return results


def index_rebalance(pool, network, assets, allocations, protocol, platform,composition=None,pairs=None):
    n = len(assets)
    if composition is None:
        composition = compositions(protocol,network,pool)

    if composition is None:
        discord(f"Error: failed to load the pool composition for rebalancing this pool: {pool} / network: {network}")
    else:
        prices = [0] * n
        balances = [0] * n
        discord(f"Rebalancing {pool} / Coins: {assets} / Target allocations: {allocations} / Protocol {protocol} / Network {network}") 
        for i in range(n):
            print(f"pulling prices for pool: {pool} / asset: {assets[i]}")
            if protocol == "dhedge":
                prices[i] = get_price(asset=assets[i], composition=composition)
            elif protocol == "defund":
                if pairs[i] == "USD-USD":
                    prices[i] = 1
                else:
                    prices[i] = get_price(asset = assets[i],composition=compopsition)

            print(f"pulling balances from composition for: {pool}")
            balances[i] = get_balance(asset=assets[i],composition=composition)

        discord(f"pairs: {assets} / target: {allocations} / prices: {prices}")
        print("pool composition")
        print(composition)
        results = index(portfolio_balances=balances, portfolio_prices=prices, target_weights=allocations)
        # Formatting multiple values from lists
        current_allocation_str = ", ".join([f"{val * 100:.2f} %" for val in results['current_allocation']])
        target_allocation_str = ", ".join([f"{val * 100:.2f} %" for val in results['target_allocation']])
        trade_amounts_str = ", ".join(map(str, results['trade_amounts']))

        # Displaying the messages
        print(f"Current allocation: {current_allocation_str}")
        print(f"Target allocation: {target_allocation_str}")
        print(f"Trade amounts: {trade_amounts_str}")

        usdc_alloc = get_allocation(asset="USDC", composition=composition)
        usdc_index = assets.index("USDC") if "USDC" in assets else None
        usdc_balance = get_balance(composition=composition, asset="USDC")

        if usdc_index is None:
            usdc_target_alloc = 0
        else:
            usdc_target_alloc = allocations[usdc_index]

        print(f"USDC allocation: {usdc_alloc}")
        print(f"USDC target allocation: {usdc_target_alloc}")
        print(f"USDC balance: {usdc_balance}")

        if protocol == "dhedge":
            # Selling every asset
            share = 0
            for i in range(n):
                if balances[i] == 0:
                    share = 0
                else:
                    share = ceil(max(results['trade_amounts'][i] / balances[i], -1) * 100)

                print(f"asset: {assets[i]} / share: {share}")

                if share < 1 and assets[i] != "USDC" and balances[i] * prices[i] > 0:
                    if toros(assets[i]):
                        platform = "toros"
                    if assets[i] == "stMATIC":
                        platform = "uniswapV3"
                    trade(from_coin=assets[i], to_coin="USDC", network=network, pool=pool, platform=platform, share=share * -1)
                    time.sleep(1)
            
            time.sleep(5)

            # Re-calculating the pool composition
            composition = compositions(protocol, network, pool)

            if composition is None:
                msg = f"Error: (trying again) failed to load the pool composition for rebalancing this pool: {pool} / network: {network}"
                send_message(message=msg, channel=channel, platform="discord")
                composition = compositions(protocol, network, pool)

            # Recalculating USDC allocations
            usdc_alloc = get_allocation(asset="USDC", composition=composition)
            usdc_index = assets.index("USDC") if "USDC" in assets else None

            if usdc_index is None:
                usdc_target_alloc = 0
            else:
                usdc_target_alloc = allocations[usdc_index]

            print(f"USDC allocation: {usdc_alloc}")
            print(f"USDC target allocation: {usdc_target_alloc}")
            usdc_balance = get_balance(composition=composition, asset="USDC")
            print(f"USDC balance: {usdc_balance}")

            for i in range(n):
                trade_amount = results['trade_amounts'][i]
                if toros(assets[i]):
                    platform = "toros"
                if assets[i] == "stMATIC":
                    platform = "uniswapV3"

                trade_bool = False
                if usdc_balance == 0:
                    share = 0
                else:
                    share = floor(min((trade_amount * prices[i]) / usdc_balance, 1) * 100)

                print(f"asset: {assets[i]} / share: {share}")

                if share > 1 and assets[i] != "USDC" and trade_amount * prices[i] > 0 and usdc_balance > 0:
                    trade(from_coin="USDC", to_coin=assets[i], platform=platform, network=network, pool=pool, share=share, protocol=protocol)
                    trade_bool = True
                    time.sleep(60)

                if trade_bool:
                    composition = compositions(protocol,network,pool )

                    if composition is None:
                        msg = f"Error: (trying again) failed to load the pool composition for rebalancing this pool: {pool} / network: {network}"
                        send_message(message = msg,channel="#pools-trading",platform="discord")
                        composition = compositions(protocol,network,pool)

                    # Recalculating USDC allocations
                    usdc_alloc = get_allocation(asset="USDC", composition=composition, prices=prices)
                    usdc_index = assets.index("USDC") if "USDC" in assets else None

                    if usdc_index is None:
                        usdc_target_alloc = 0
                    else:
                        usdc_target_alloc = allocations[usdc_index]

                    print(f"USDC allocation: {usdc_alloc}")
                    print(f"USDC target allocation: {usdc_target_alloc}")
                    usdc_balance = get_balance(composition=composition, asset="USDC")
                    print(f"USDC balance: {usdc_balance}")


def delta_neutral_yield():
    pool = "0xc3ffa8d537e31ebf83e7f5f43b481c8101545352"
    network = "polygon"
    platform = "uniswapV3"
    protocol = "dhedge"
    assets = ["stMATIC", "MATICBEAR1X", "USDC"]
    allocations = [0.50, 0.50, 0]
    index_rebalance(pool, network, assets, allocations, protocol,platform)

def optimism100x():
    pool="0x0e7ba4af3b39c8fd5cc5619aecdfecb3316fd6a1"
    network="optimism"
    protocol="dhedge"
    platform="uniswapV3"
    composition = compositions(protocol,network,pool)
    usdc_allocation = get_allocation(asset="USDC", composition=composition)
    usdmny_allocation = get_allocation(asset="USDmny", composition=composition)
    dht_allocation = get_allocation(asset="USDmny",composition=composition)
    usd_alloc = usdc_allocation + usdmny_allocation
    velo_allocation = get_allocation(asset="VELO",composition=composition)
    snx_allocation = get_allocation(asset="SNX",composition=composition)
    if usdc_allocation > 0.025:
        if usd_alloc < 0.30:
            trade(from_coin="USDC", to_coin="USDmny", network=network, pool=pool, platform=platform, share=1)
            time.sleep(20)
            composition = compositions(protocol,network,pool)
            time.sleep(1)
        else:
            rebalance_assets = True
    if dht_allocation >= 0.125 or dht_allocation <= 0.085:
        rebalance_assets = True
    elif velo_allocation <=0.25 or velo_allocation >=0.35:
        rebalance_assets= True
    elif snx_allocation <= 0.25 or snx_allocation >=0.35:
        rebalance_assets= True
    assets = ["VELO","SNX","USDmny","DHT"]
    allocations=[0.30,0.30,0.30,0.10]
    #min_list = get_minmax_from_composition(composition,which="min",allowed_assets=assets)
    #max_list = get_minmax_from_composition(composition,which="max",allowed_assets=assets)
    #min_asset = min_list['asset']
    #max_asset = max_list['asset']
    #min_asset_allocation = min_list['allocation']
    #max_asset_allocation = max_list['allocation']
    #if max_asset_allocation >= 0.35 or min_asset_allocation <= 0.25 or rebalance_assets:
    if rebalance_assets:
        index_rebalance(pool,network,assets,allocations,protocol,platform,composition=composition)

optimism100x()
