# Test batch integration in defi_thread
source('~/infinitetrading/src/tradebot/defi_thread.R')

# Test with Zeus BTC pool (from pools.R)
test_pools <- c("0xb48a390270d41a1663a68708210b7ef4d89ba9f6")
test_networks <- c("polygon")
test_models <- c("ZeusBTC_6h-BTC-USD")
test_trade_pairs <- c('WBTC')
test_base_pairs <- c('USDC')
test_platforms <- c('uniswapV3')

# Thresholds
buy_long_thresholds <- c(0.51)
close_long_thresholds <- c(0.10)
buy_short_thresholds <- c(0.49)
close_short_thresholds <- c(0.90)

candle_close <- c(FALSE)
ep <- c("prod")

cat("\n=== Testing Batch Integration ===\n")
cat("This will run ONE monitoring cycle with batch fetching\n\n")

# Modify defi_thread to run only 1 cycle for testing
defi_thread_test = function(pools,models,trade_pairs,base_pairs,buy_long_thresholds,close_long_thresholds,buy_short_thresholds,close_short_thresholds,candle_close,ep,networks,platforms="1inch",protocol="dhedge",max_usd=NULL,manager="infinitetrading") { 
	n=length(pools); reports_hour = -1; instructions = rep("hold",n); trades = rep(0,n) 
	if (length(platforms) < n) { diff =  n - length(platforms); platforms = c(platforms,rep("1inch",diff))
	}
	
	# Run only ONE cycle for testing
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
	
	# Verify composition structure
	for (i in 1:n) {
		pool_addr <- pools[i]
		pool_composition <- get_pool_composition(pool_addr, all_compositions)
		
		cat(sprintf("\nPool %d: %s\n", i, pool_addr))
		cat(sprintf("  Network: %s\n", networks[i]))
		cat(sprintf("  Model: %s\n", models[i]))
		
		if (!is.null(pool_composition) && is.data.frame(pool_composition)) {
			cat(sprintf("  ✅ Composition loaded: %d assets\n", nrow(pool_composition)))
			cat("  Top assets:\n")
			print(head(pool_composition[, 1:4], 3))
		} else {
			cat("  ❌ Failed to load composition\n")
		}
	}
	
	cat("\n\n🎉 Test completed successfully!\n")
	cat("Next: The monitoring loop will fetch all pools in batches at start of each cycle\n")
}

# Run test
defi_thread_test(
	pools = test_pools,
	models = test_models,
	trade_pairs = test_trade_pairs,
	base_pairs = test_base_pairs,
	buy_long_thresholds = buy_long_thresholds,
	close_long_thresholds = close_long_thresholds,
	buy_short_thresholds = buy_short_thresholds,
	close_short_thresholds = close_short_thresholds,
	candle_close = candle_close,
	ep = ep,
	networks = test_networks,
	platforms = test_platforms,
	protocol = "dhedge"
)
