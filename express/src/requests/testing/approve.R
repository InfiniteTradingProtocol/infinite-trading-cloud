# Load httr package
library(httr)

# Define the base URL and parameters
dhedge_ep <- "http://localhost:8000/approve?&pool="

#params <- list(
#  pool = "0x37849922d4b071254e25aa036a94442b059fdb60",
#  asset = "0x68f180fcce6836688e9084f035309e29bf0a2095",
#  platform = "uniswapV3",
#  network = "optimism",
  #estimateGas = "true",
#  manager="infinitetrading"
#)

# Send :wqET request
#response <- GET(url = base_url, query = params)
#content_response= content(response,"text")
#print(response)
# Check the response and extract the output
#if (status_code(response) == 200) {
#  cat("Response received successfully:\n", content_response)
#} else {
#  cat("Failed to retrieve data. Status code:", status_code(response))
#}

dhedge_ep2="https://us-central1-dhedge-trading.cloudfunctions.net/approve?apiKey=RzdpGs9RnDMxf6ReWspa6bZF5t8ecKLy&pool="

#approve_assets=function(pool,asset,network="optimism",estimateGas=FALSE,toros=FALSE,platform=NULL,manager="infinitetrading",dhedgeAPI=TRUE,provider=NULL,providerKey=NULL) {
#	require(httr);require(jsonlite)
#    	if (network == "optimism" && dhedgeAPI) ep = paste0(dhedge_ep2,pool)
#    	else ep = paste0(dhedge_ep,pool)
#    	if (!is.null(manager)) { ep = paste0(ep,"&manager=",manager) }
#    	if (toros) { ep = paste0(ep,"&platform=toros") }
#    	if (estimateGas) { ep = paste0(ep,"&estimateGas=true") }
#    	if (!is.null(platform)) { ep = paste0(ep,"&platform=",platform) }
#    	if (!is.null(network)) { ep = paste0(ep,"&network=",network) }
#    	ep = paste0(ep,"&asset=",asset)
#    	res = POST(url=ep,encode="json")
#    	res = fromJSON(content(res,as="text"))
#    	print(res)
#}

approve_assets=function(pool,assets,env="dev",network,provider='infura',apiKey=NULL,toros=FALSE,platform=NULL,manager=NULL) {
  require(httr); require(jsonlite); n = length(assets)
  if (length(toros) != n) toros = rep(toros[1],n)
  for (i in 1:n) {
    ep = paste0(dhedge_ep,pool)
    if (!is.null(manager)) ep = paste0(ep,"&manager=",manager)
    if (toros[i]) ep = paste0(ep,"&platform=toros")
    if (!is.null(platform)) ep = paste0(ep,"&platform=",platform)
    if (!is.null(apiKey)) ep = paste0(ep,"&apiKey=",apiKey)
    if (!is.null(provider)) { ep = paste0(ep,"&provider=",provider) }
    ep = paste0(ep,"&network=",network)
    res = POST(url=ep,body=list(asset=assets[i]),encode="json")
    Sys.sleep(5)
    res = fromJSON(content(res,as="text"))
    print(res)
    print(unlist(res$msg))
  }
}

#approve_assets(pool="0x159b88ab8e27956586c7ac7e77a606115959de15",apiKey="1405b8a4e6713f0615a200f6536b833bb3f4057f50bb4b52d91dfa6e29a63c7d0730826955c05870579ba903dc0ebde7f10b12f1e56e2d9368deec0aa758e9b3",asset="0x0b2c639c533813f4aa9d7837caf62653d097ff85",platform="uniswapV3",network="optimism")

#approve_assets(pool="0x159b88ab8e27956586c7ac7e77a606115959de15",apiKey="1405b8a4e6713f0615a200f6536b833bb3f4057f50bb4b52d91dfa6e29a63c7d0730826955c05870579ba903dc0ebde7f10b12f1e56e2d9368deec0aa758e9b3",asset="0x7f5c764cbc14f9669b88837ca1490cca17c31607",platform="toros",network="optimism")


#approve_assets(pool="0x159b88ab8e27956586c7ac7e77a606115959de15",apiKey="1405b8a4e6713f0615a200f6536b833bb3f4057f50bb4b52d91dfa6e29a63c7d0730826955c05870579ba903dc0ebde7f10b12f1e56e2d9368deec0aa758e9b3",asset="0xcacb5a722a36cff6baeb359e21c098a4acbffdfa",platform="toros",network="optimism")
#API TESTING WALLET KEY: cb98542ff8b15b5a35c9583e6facf91b38096f54d2bb4f0efc70b2a70718c66730ee441a9e9923e1fa6f53391e9008ed6834aa3caee451c1a0873055eb56f5ee
#ZEUS AI BTC POOL: 0x34358e00aacaf1071c832266859b64b085a1c1ae
#WBTC CONTRACT:  0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6

approve_assets(pool="0x34358e00aacaf1071c832266859b64b085a1c1ae",provider="alchemy",apiKey="cb98542ff8b15b5a35c9583e6facf91b38096f54d2bb4f0efc70b2a70718c66730ee441a9e9923e1fa6f53391e9008ed6834aa3caee451c1a0873055eb56f5ee",asset="0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6",platform="uniswapV3",network="polygon")

#approve_assets(pool="0xf35b6bd6f5dcfc18498f8e166821cf8713645005",apiKey="0e5be968b6cac0fa61c9ab89db2ff84e2b198dc94dd331ccacea98cbafe490b1fae0779825d56261c4b1d6994943788ed1ae1e12db9d52e345c5b8cbfdadb988",asset="0x3c499c542cef5e3811e1192ce70d8cc03d5c3359",platform="uniswapV3",network="polygon")
#approve_assets(pool="0x37849922d4b071254e25aa036a94442b059fdb60",apiKey="8bcde4590eeaacf0b235f2d7d49dcd15761df4a89e617bd71c897867d3ea25166e3841ea73413573111a75ee9a1e858b4a83cb84d94d42943e23eaea4e7493bb",asset="0x68f180fcce6836688e9084f035309e29bf0a2095",platform="uniswapV3",network="optimism")
