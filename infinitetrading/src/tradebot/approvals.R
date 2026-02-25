wd = "~/infinitetrading/src/tradebot/"
source(paste0(wd,"defi.R"))
approve_assets(pool="0xb48a390270d41a1663a68708210b7ef4d89ba9f6",assets=c("WBTC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
return(0)

#BTC BULL AND BEAR
approve_assets(pool="0x34358e00aacaf1071c832266859b64b085a1c1ae",assets=c("WBTC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0x34358e00aacaf1071c832266859b64b085a1c1ae",assets=c("BTCBEAR1X","USDC"),platform="toros",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#ETH BULL AND BEAR WITH LEVERAGE
approve_assets(pool="0xe8f78aaa6ac51db0ea5fe64340cbe724c2fa0079",assets=c("ETHBULL3X"),platform="toros",network="polygon",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xe8f78aaa6ac51db0ea5fe64340cbe724c2fa0079",assets=c("USDC","ETHBEAR2X"),platform="toros",network="polygon",manager="infinitetrading")

#BTC LONG ONLY
Sys.sleep(5)
approve_assets(pool="0xb48a390270d41a1663a68708210b7ef4d89ba9f6",assets=c("WBTC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")

#LINk LONG ONLY
Sys.sleep(5)
approve_assets(pool="0xb990f805c16b65eb9400a390fd9087e4a249e681",assets=c("LINK","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#DELTA NEUTRAL STMATIC
approve_assets(pool="0xc3ffa8d537e31ebf83e7f5f43b481c8101545352",assets=c("stMATIC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xc3ffa8d537e31ebf83e7f5f43b481c8101545352",assets=c("MATICBEAR1X","USDC"),platform="toros",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#Inflation Hedge
approve_assets(pool="0xd8e1ed48f2ff726642e1caeae2dafc8a2f9aef01",assets=c("stMATIC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xd8e1ed48f2ff726642e1caeae2dafc8a2f9aef01",assets=c("MATICBEAR1X","USDC"),platform="toros",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#eth long and short
approve_assets(pool="0x705ad85c3c3a065bc87c49598e1dd2f1b9324663",assets=c("WETH","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0x705ad85c3c3a065bc87c49598e1dd2f1b9324663",assets=c("ETHBEAR1X","USDC"),platform="toros",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#Infinite Bitcoin Trading
approve_assets(pool="0xc3f232c00ab6ce31a332126331da3f74ca1d51cc",assets=c("USDC"),platform="toros",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xc3f232c00ab6ce31a332126331da3f74ca1d51cc",assets=c("BTCBEAR1X"),platform="toros",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xc3f232c00ab6ce31a332126331da3f74ca1d51cc",assets=c("USDC"),platform="uniswapV3",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xc3f232c00ab6ce31a332126331da3f74ca1d51cc",assets=c("WBTC"),platform="uniswapV3",network="optimism",manager="infinitetrading")
Sys.sleep(5)
#Optimism delta neutral

approve_assets(pool="0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c",assets=c("USDC"),platform="uniswapV3",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c",assets=c("WSTETH"),platform="uniswapV3",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c",assets=c("ETHBEAR1X"),platform="toros",network="optimism",manager="infinitetrading")
Sys.sleep(5)
approve_assets(pool="0xd1fcc6cfa3053c148d1f84424e47cefab45e0b8c",assets=c("USDC"),platform="toros",network="optimism",manager="infinitetrading")
Sys.sleep(5)
#SOL LONG ONLY
approve_assets(pool="0x7e95ed8b07155c7f212ce891391d512757438f01",assets=c("SOL","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")
Sys.sleep(5)
#MATIC LONG ONLY
approve_assets(pool="0xf35b6bd6f5dcfc18498f8e166821cf8713645005",assets=c("stMATIC","WMATIC","USDC"),platform="uniswapV3",network="polygon",manager="infinitetrading")


