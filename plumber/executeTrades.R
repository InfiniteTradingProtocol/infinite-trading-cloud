executeTrades = function(pool,pair,share,network,threshold,slippage,platform,protocol,max_usd,composition,side,apiKey) {
        res = tryCatch({
        print(paste0("executeTrades invoked using this api key: ",apiKey))
        if (is.null(composition)) { composition=pool_comp(network=network,protocol=protocol,pool=pool) }

        #I have the pool composition
        #If toros is not in the pool composition, then do not do the 'again' for efficiency

        split_string <- strsplit(pair, "-")
        trade_pair = split_string[[1]][1]; base_pair = split_string[[1]][2]; pair = paste(trade_pair,base_pair,sep="-")
        price = get_usd_price(asset=trade_pair,composition=composition)
        print(paste0("network: ",network," / pair: ",pair," / pool: ",pool," / price: ",round(price,4)," / side: ",side))

        if (side == "long") { tradebot(pool=pool,pair=pair,share=share,slippage=slippage,threshold=threshold,side = "buy",price=price,network = network,platform=platform,protocol=protocol,max_usd=max_usd,apiKey=apiKey,pool_composition=composition) }
        else if (side == "neutral") {
                print("sending sell to dhedgev2")
                tradebot(pool=pool,pair=pair,share=share,slippage=slippage,threshold=threshold,side = "sell",price=price,network = network,platform=platform,protocol=protocol,max_usd=max_usd,apiKey=apiKey,pool_composition=composition)
                again=FALSE
                if (any(short_networks == network)) {
                        if (is_btc(trade_pair)) { bear_token = "BTCBEAR1X"; pair = "BTCBEAR1X-USDC"; again =TRUE }
                        else if (is_eth(trade_pair)) { bear_token = "ETHBEAR1X"; pair = "ETHBEAR1X-USDC"; again = TRUE }
                }
                if (again) { #add here && (bear_token is in composition) { execute }
                        response = tradebot(pool=pool,platform="toros",pair=pair,share=share,slippage=slippage,threshold=threshold,side = "sell",price=price,network=network,protocol=protocol,apiKey=apiKey,max_usd=max_usd,pool_composition=composition); print(paste("tradebot response:",response)) }
        }
        else if (side == "short") {
                print("selling the trade asset invoking tradebot")
                response = tradebot(pool=pool,pair=pair,share=share,slippage=slippage,threshold=threshold,side = "sell",price=price,network=network,platform=platform,protocol=protocol,max_usd=max_usd,apiKey=apiKey,pool_composition=composition)
                print(paste("tradebot response:",response))
                again = FALSE
                if (any(short_networks == network)) {
                        if (is_btc(trade_pair)) { pair = "BTCBEAR1X-USDC"; again=TRUE }
                        else if (is_eth(trade_pair)) { pair = "ETHBEAR1X-USDC"; again=TRUE }
                }
                if (again) {
                        print("buying the short side of the trade")
                        response = tradebot(pool=pool,pair=pair,share=share,slippage=slippage,threshold=threshold,side = "buy",price=price,platform="toros",network=network,protocol=protocol,max_usd=max_usd,apiKey=apiKey,pool_composition=composition)
                        print(paste("tradebot response:",response))
                }
                list(status="success",status_code=200,message="executeTrades succesfully invoked")
        }
        else if (side == "hold") { list(status="success",status_code=200,message="executeTrades succesfully invoked") }
        },error = function(e) { list(status="fail",status_code="400",message=e) })
        Sys.sleep(1)
        return(res)
}
