source('~/infinitetrading/src/tradebot/tradebot.R')
source('~/infinitetrading/src/api/pool_comp_batch.R')
require(lubridate)


defi_thread = function(pools,models,trade_pairs,base_pairs,buy_long_thresholds,close_long_thresholds,buy_short_thresholds,close_short_thresholds,candle_close,ep,networks,platforms="1inch",protocol="dhedge",max_usd=NULL,manager="infinitetrading") { 
	n=length(pools); reports_hour = -1; instructions = rep("hold",n); trades = rep(0,n) 
	if (length(platforms) < n) { diff =  n - length(platforms); platforms = c(platforms,rep("1inch",diff))
	}
	while (1) {
		this_hour = hour(Sys.time())
		
		# 🚀 BATCH FETCH: Get all pool compositions at once, grouped by network
		cat("\n🔄 Fetching pool compositions in batches...\n")
		all_compositions <- list()
		unique_networks <- unique(networks)
		
		for (net in unique_networks) {
			network_pool_indices <- which(networks == net)
			network_pools <- pools[network_pool_indices]
			
			if (length(network_pools) > 0) {
				cat(sprintf("  📦 Network %s: %d pool(s)\n", net, length(network_pools)))
				batch_result <- tryCatch({
					fetch_batch_compositions(network_pools, net)
				}, error = function(e) {
					cat(sprintf("  ❌ Error fetching %s pools: %s\n", net, e$message))
					list()
				})
				
				# Store compositions with pool address as key
				for (pool_addr in names(batch_result)) {
					all_compositions[[pool_addr]] <- batch_result[[pool_addr]]
				}
			}
		}
		cat(sprintf("✅ Fetched %d pool compositions\n\n", length(all_compositions)))
		cat(sprintf("✅ Fetched %d pool compositions\n\n", length(all_compositions)))
		
		# Process each pool with pre-fetched composition
		for (i in 1:n) {
			old_instruction = instructions[i]
			pool_addr <- pools[i]
			
			# Get pre-fetched composition for this pool
			pool_composition <- get_pool_composition(pool_addr, all_compositions)
			probabilities = read_probabilities()
			print(probabilities)
                        if (is.null(probabilities) || !is.data.frame(probabilities) || nrow(probabilities) == 0) { print(paste0("ERROR: No probabilities data for model ", models[i])); next }
			#anadir aqui si es nulo un next para que brinque al proximo e imprima un error.
			indexes = probabilities[,1] == models[i]
 			actual_prob = probabilities[indexes,4]
			if (candle_close[i]) { buy_prob = probabilities[indexes,3] }
			else { buy_prob = probabilities[indexes,4] }
			price = probabilities[indexes,5]
			pair1 = trade_pairs[i]; pair2 = base_pairs[i];
			endpoint = NULL;
			if (buy_prob >=buy_long_thresholds[i]) { pair1=trade_pairs[i]; pair2 = base_pairs[i]; instructions[i] = "long" }
			else if (buy_prob <= close_long_thresholds[i]) { instructions[i] = "neutral" }
			if (buy_prob >= close_short_thresholds[i] && buy_prob <= close_long_thresholds[i] && buy_long_thresholds[i] != buy_short_thresholds[i]) { instructions[i] = "neutral " } 
			else if (buy_prob <= buy_short_thresholds[i]) { pair1 = base_pairs[i]; pair2 = trade_pairs[i]; instructions[i] = "short" }
			
			if (instructions[i] == "neutral") { pair1=base_pairs[i]; pair2 = base_pairs[i]; } 		
			side = instructions[i]
			pair = paste(trade_pairs[i],base_pairs[i],sep="-")
			print(paste0("network: ",networks[i]," / pair: ",pair," / pool: ",pools[i]," / price: ",round(price,4)," / side: ",side,"/ prob: ",buy_prob," / model: ",models[i]," / buy long: ",buy_long_thresholds[i]," / close long: ",close_long_thresholds[i]))
			if (is_toros(trade_pairs[i])) { price = 0 }
			if (side == "long") { 
				print("sending buy to dhedgev2")
				tradebot(pool=pools[i],pair=pair,share=100,slippage=0.5,threshold=0.5,side = "buy",price=price,ep =ep[i],network = networks[i],platform=platforms[i],protocol=protocol,max_usd=max_usd,manager=manager,pool_composition=pool_composition)
			}
			else if (side == "hold") {
				tradebot(pool=pools[i],pair=pair,share=100,slippage=0.5,threshold=0.5,side = "hold",price=price,ep =ep[i],network = networks[i],platform=platforms[i],protocol=protocol,max_usd=max_usd,manager=manager,pool_composition=pool_composition)
			}
			else if (side == "neutral") { 
				print("sending sell to dhedgev2")
				tradebot(pool=pools[i],pair=pair,share=100,slippage=0.5,threshold=0.5,side = "sell",price=price,ep=ep[i],network = networks[i],platform=platforms[i],protocol=protocol,max_usd=max_usd,manager=manager,pool_composition=pool_composition)
				again =FALSE
				if (trade_pairs[i] == "BTCBULL3X") { pair = "BTCBEAR2X-USDC"; again =TRUE }
                                else if (trade_pairs[i] == "ETHBULL3X") { pair = "ETHBEAR2X-USDC"; again = TRUE }
                                else if (trade_pairs[i] == "MATICBULL2X") { pair = "MATICBEAR1X-USDC"; again=TRUE }
				else if (trade_pairs[i] == "WBTC") { pair ="BTCBEAR1X-USDC"; again=TRUE }
				else if (trade_pairs[i] == "WETH") { pair = "ETHBEAR1X-USDC"; again=TRUE }
				if (again) { tradebot(pools[i],pair,share=100,slippage=2,threshold=0.5,side = "sell",price=price,ep=ep[i],network=networks[i],protocol=protocol,manager=manager,pool_composition=pool_composition) }
			}
			else if (side == "short") {
				tradebot(pools[i],pair,share=100,slippage=0.5,threshold=0.5,side = "sell",price=price,ep=ep[i],network=networks[i],platform=platforms[i],protocol=protocol,max_usd=max_usd,manager=manager,pool_composition=pool_composition)
				again = FALSE
				if (trade_pairs[i] == "BTCBULL3X") { pair = "BTCBEAR2X-USDC"; again=TRUE } 
				else if (trade_pairs[i] == "WBTC") { pair = "BTCBEAR1X-USDC"; again=TRUE }
				else if (trade_pairs[i] == "ETHBULL3X") { pair = "ETHBEAR2X-USDC"; again=TRUE } 
				else if (trade_pairs[i] == "WETH") { pair = "ETHBEAR1X-USDC"; again = TRUE }
				else if (trade_pairs[i] == "WMATIC" || trade_pairs[i] == "MATICBULL2X") { pair = "MATICBEAR1X-USDC"; again=TRUE } 
				if (again) { tradebot(pools[i],pair,share=100,slippage=0.5,threshold=0.5,side = "buy",price=price,ep=ep[i],network=networks[i],protocol=protocol,manager=manager,pool_composition=pool_composition) }
			}
			if (this_hour != report_hour) {
				tryCatch(discord(msg=paste0(i,". ",networks[i]," / ", models[i]," / ",platforms[i], " / ", paste(trade_pairs[i],base_pairs[i],sep="-"), " / ",instructions[i]," / Prob: ",round(buy_prob,2)," / Long: ",buy_long_thresholds[i]," / NoLong: ",close_long_thresholds[i]," / Short: ",buy_short_thresholds[i]," / NoShort:", close_short_thresholds[i]),channel=ifelse(protocol=="dhedge","#dhedge-pools","#defund-pools")))
			}
			Sys.sleep(5)
			# add here ^^ if (side != old side) and return sides from the tradebot as in the coinbase)

		} 
		if (this_hour != report_hour) { trades = rep(0,n) ;report_hour = this_hour } 
		Sys.sleep(30)
	}
}


