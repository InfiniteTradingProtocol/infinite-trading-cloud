
#####################
# d H e d g e Pools #
# Infinite Trading  #
#####################

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
# Source main.R to get discord() function
if (file.exists(paste0(wd,'strategies/main.R'))) {
  source(paste0(wd,'strategies/main.R'))
}
discord(msg="Warning: Pools thread initializing...",channel="#error-logs")
models=c (#"ZeusBTC_6h-LINK-USD-C-0.30-0.70", #1
	  "ZeusBTC_6h-BTC-USD"		     #2
	 #"ZeusBTC_6h-ETH-USD",	 	     #3
	 #"HeraBTC_1d-MATIC-USD", 	     #4
	 # "ZeusBTC_6h-BTC-USD-HA",	     #5
	 #"HeraBTC_1d-ETH-USD",	 	     #6
	 #"ZeusBTC_6h-SOL-USD-CBE-0.50-0.30-0.20", #7
	 #"HeraBTC_1d-BTC-USD",	 	     #8	 
	 #"ZeusBTC_6h-MATIC-USD-CBE-0.30-0.30-0.30", #9
	 #"HeraBTC_1d-ETH-USD",		     #15
	 #"HeraBTC_1d-ETH-USD", 	     #16
	 #"HeraBTC_1d-ETH-USD",   	     #17
	 #"ZeusBTC_6h-OP-USD",	 	     #19
	 #"ZeusBTC_6h-BTC-USD",	 	     #20
         #"ZeusBTC_6h-ETH-USD",	 	     #21
	 #"ZeusBTC_6h-SNX-USD",	 	     #22
	 #"ZeusBTC_6h-ETH-USD-HA" 	     #24
	 #"ZeusBTC_6h-OP-USD",	 	     #25
	 #"MomentumBTC_6h-BTC-USD-S" 	     #26
)
n = length(models)
trade_pairs=c(
	      # 'LINK',		#1
	      'WBTC'		#2
	      # 'WETH',		#3
	      # 'MATICBULL2X',	#4
	      # 'WBTC',		#5
	      # 'ETHBULL3X',		#6
	      # 'SOL',		#7
	      # 'WBTC',		#8
	      # 'stMATIC',	#9
	      # 'WSTETH',		#15
	      # "ETHBULL3X",    	#16
	      # "BTCBULL3X",	#17
	      # "OP",		#19
	      # "WBTC",		#20
	      # "ETHy",		#21
	      # "SNX",		#22
	      # "WETH"		#24
	      #"OP",		#25
	      #"WBTC"		#26
)
max_usd = c(
	    #500,	#1
	    1000	#2
	    #5000,	#3
	    # 1000,	#5
	    #2500,	#6
	    # 500,	#7
	    #500,	#9
	    #1000,	#20
	    #5000	#24
	   )
base_pairs= c(
	      # 'USDC',		#1
	      'USDC'		#2
	      # 'USDC',		#3
	      # 'USDC',		#4 THIS
	      # 'USDC',		#5
	      # 'USDC',		#6
	      # 'USDC',		#7
	      # 'USDC',		#8
	      # 'USDC',		#9
	      # 'USDmny',		#15
	      # 'USDC',		#16
	      # 'USDC',		#17
	      #"USDC",		#19
	      # "USDC",		#20
	      #"USDC",		#21
	      #"USDC",		#22
	      # "USDC"		#24
	      #"USDmny",		#25
	      #"USDmny"		#26
)
platforms = c(
	      # 'uniswapV3',	#1
	       'uniswapV3'		#2
	      # 'uniswapV3',	#3 (approved)
	      # 'toros',		#4 (approved)
	      # 'uniswapV3',	#5 
	      # 'toros',	#6 (approved)
	      # 'uniswapV3', #7
	      # 'quickswap',	#8 (approved)
	      # 'uniswapV3', 	#9
	      # 'uniswapV3',	#15 (approved)
	      # 'toros',		#16 (approved)
	      # 'toros',		#17
	      # "uniswapV3",	#19
	      # "uniswapV3",	#20
	      # "uniswapV3",	#21
	      # "uniswapV3",	#2
	      # "uniswapV3"	#24
	      # "uniswapV3",	#25
	      # "uniswapV3"	#26
)
buy_long_thresholds=  c(
			#0.60,	#1
			0.51	#2
			#0.50,	#3
			# 0.55,	#4
			#0.50,	#5
			#0.53,	#6
			# 0.50,	#7
			# 0.53,	#8
			#0.50,	#9
			#0.60,	#15
			#0.65,   #16
			#0.55,	#17
			#0.50,	#19
			#0.50,	#20
			#0.50,	#21
			#0.50,	#22
			#0.50	#24
			#0.45,	#25
			#0.50	#26
)		
close_long_thresholds=c(#0.10,	#1
			0.10	#2
			#0.10,	#3
			# 0.28,	#4
			#0.10,	#5
			#0.30,	#6
			#0.10,  #7
			#0.27,	#8
			#0.10,	#9
			#0.40,	#15
			#0.35, 	#16
			#0.45,	#17
			#0.30,  #19
			#0.30,	#20
			#0.30,	#21
			#0.30,	#22
			#0.10	#24
			#0.10,	#25
			#0.30	#26
)
buy_short_thresholds= c(
			#-1,	#1
			-1	#2
			#0.10,	#3
			# 0.28,	#4
			#-1,    #5
			#0.30,	#6
			#-1,    #7
			#0.27,	#8
			#-1,	#9
			#-1,	#15
			#0.35,	#16
			#0.45,	#17
			#-1,	#19
			#0.30,	#20
			#-1,	#21
			#-1,	#22
			#-1	#24
			#-1,	#25
			#-1	#26
			)
close_short_thresholds=	c(
			 #2,	#1
			 2	#2
			 #0.50,  #3
			 # 0.55,#4
			 #2,     #5
			 #0.53,	#6
			 #2,    #7
			 #0.53,	#8
			 #2,	#9
			 #2,	#15
			 #0.65,	#16
			 #0.55,	#17
			 #2,	#19
			 #0.50,	#20
			 #2,	#21
			 #2,	#22
			 #2   	#24
			 #2,	#25
			 #2	#26
			)
candle_close=c(
	       #FALSE,		#1
	       TRUE		#2
	       #TRUE,		#3
	       # TRUE,		#4
	       #FALSE,		#5
	       #FALSE,		#6
	       #FALSE,          #7
	       #FALSE,		#8
	       #FALSE,		#9
	       #FALSE,		#15
	       #FALSE,		#16
	       #FALSE,		#17
	       #FALSE,		#19
	       #FALSE,		#20
	       #FALSE,		#21
	       #FALSE,		#22
	       #FALSE		#24
	       #FALSE,		#25
	       #FALSE		#26
)
report_hour = -1
pools = c(
	  #"0xb990f805c16b65eb9400a390fd9087e4a249e681",	#1
	  "0xb48a390270d41a1663a68708210b7ef4d89ba9f6" #2
	  #"0x705ad85c3c3a065bc87c49598e1dd2f1b9324663", #3
	  # "0x2a09812dbba5dd84a4a63038b1cc65f5f7e9229d",#4
	  #"0x37849922d4b071254e25aa036a94442b059fdb60",#5
	  #"0xe8f78aaa6ac51db0ea5fe64340cbe724c2fa0079",#6
	  #"0x7e95ed8b07155c7f212ce891391d512757438f01",#7
	  #"0xa6401a83012b6807ce8315434922183119abce50",#8
	  #"0xf35b6bd6f5dcfc18498f8e166821cf8713645005",#9
	  #"0x94d04ac402aab96e259e031986fcbcceaaa44189",#15
	  #"0xceac05e35d9d928168b8a9c990baeb3b921b0c97",#16
	  #"0x1326145e6cb4f5c37e30c29487017e6422df88b3",#17
	  #"0x84f8f0b0007bed6f9d79c7f9751dce2c2432b34a",#19
	  #"0x34358e00aacaf1071c832266859b64b085a1c1ae", #20
	  #"0xd228da239c09a9f3083af45f035edc258139c5ec",#21
	  #"0xbee17540d4cd107f512968f852240da3610f1e53",#22
	  #"0x0693ef3a503c3653538963cc0a58e897a3cb0501"	#24
	  #"0x0889d928cf4e6841d6a55822b521524096b34320",#25
	  #"0xc3f232c00ab6ce31a332126331da3f74ca1d51cc" #26
)
ep = rep("local",n)
networks = c( 
	     #"polygon",	  #1
	     "polygon"   #2
     	     #"polygon",   #3
	     # "polygon", #4
	     #"optimism",  #5
	     #"polygon",   #6    
	     #"polygon", #7
	     #"polygon",#8
	     #"polygon", #9
	     #"optimism", #15
	     #"polygon",#16
	     #"polygon",#17
	     #"optimism",#19
	     #"polygon", #20
	     #"optimism", #21
	     #"optimism", #22
	     #"polygon"	 #24
	     #"optimism", #25
	     #"optimism"  #26
)
defi_thread(pools,models,trade_pairs,base_pairs,buy_long_thresholds,close_long_thresholds,buy_short_thresholds,close_short_thresholds,candle_close,ep,networks,platforms=platforms,protocol="dhedge",max_usd=max_usd,manager="infinitetrading")
