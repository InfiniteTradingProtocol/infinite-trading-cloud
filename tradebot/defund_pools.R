# Dynamic path detection - works in both local and EC2 environments
if (!exists("wd")) {
  if (exists("ofile") && !is.null(ofile <- sys.frame(1)$ofile)) {
    script_dir = dirname(normalizePath(ofile))
  } else {
    script_dir = normalizePath(".")
  }
  # Navigate up from tradebot/ to repo root
  wd = paste0(dirname(script_dir), "/")
}
source(paste0(wd,'tradebot/defi_thread.R'))

models=c(
	 #"HeraBTC_1d-ETH-USD",	 #1
	 "ZeusBTC_6h-BTC-USD",	 #2
	 "ZeusBTC_6h-ETH-USD",	 #3
	 #"HeraBTC_1d-ETH-USD",	 #4
	 "ZeusBTC_6h-BTC-USD"	 #5
)
trade_pairs = c(
	      # 'WETH',		#1
	      'WBTC',		#2
	      'WETH',		#3
	      # 'WETH',		#4
	      'WBTC'		#5
)
base_pairs= c(
	       # 'USDC',	#1
	       'USDC',		#2
	       'USDC',		#3
	       # 'USDC',	#4
	       'USDC'		#5
)
platforms = c(
	      # 'UNISWAPV3',	#1
	      'UNISWAPV3',	#2
	      'UNISWAPV3',	#3
      	      # 'UNISWAPV3',	#4
	      'UNISWAPV3'	#5      
)
buy_long_thresholds=  c(
			#0.53,	#1
			0.50,	#2
			0.50,	#3
		 	#0.50,	#4
		        0.50	#5	
)		
close_long_thresholds=c(
			#0.30,	#1
			0.30,	#2
			0.10,	#3
			#0.30,	#4
			0.20	#5
)
buy_short_thresholds= c(
			#-1,	#1
			-1,	#2
			-1,	#3
			#-1,	#4
			-1
			)
close_short_thresholds=	c(
			 #2,	#1
			 2,	#2
			 2,	#3
			 #2,	#4
			 2	#5
			)
candle_close=c(
	       #FALSE,		#1
	       FALSE,		#2
	       FALSE,		#3
	       #FALSE,		#4
	       FALSE		#5
)
report_hour = -1
pools = c(
	  #"0xC215C4Ea25f19Bf73245a75CCbc7eAC7CfFcF508", #1
	  "0xA20Af31f60e4Fed4F2b80B6045B5b1E15aB55819", #2
	  "0xC5e119Fd78B1b3582954f7280551A500780C0A62", #3
	  #"0xc3060C6E1479865e7359005dE9522905eb412b38" #4
	  "0x7adE348d16e6b3D36fd7841Db921C0acFDe5a674" #5
)
n = length(pools)
ep = rep("local",n)
networks = c( 
	     #"polygon", #1
	     "polygon", #2
	     "polygon",	#3
	     #"arbitrum",#4
	     "polygon"  #5
)
defi_thread(pools,models,trade_pairs,base_pairs,buy_long_thresholds,close_long_thresholds,buy_short_thresholds,close_short_thresholds,candle_close,ep,networks,platforms=platforms,protocol="defund")
