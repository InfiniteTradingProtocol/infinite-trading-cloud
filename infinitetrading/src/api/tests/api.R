library(httr)
library(jsonlite)

itp_api = function(endpoint,params) { 
	# The URL of the API endpoint
	url <- paste0("http://localhost:8003/",endpoint)
	if (endpoint == "trade") { 
	 	#use POST
	}
	else { response = GET(url,query=params) }  
  	content <- content(response, "text", encoding = "UTF-8")
  	cat("Response from API:", content, "\n")
	#return(fromJSON(content))
	#if (endpoint == "createWallet") {
		#parsed_response = fromJSON(content)
        	# Extract address and private key
        	#address <- parsed_response$address
        	#private_key <- parsed_response$privateKey

        	# Print address and private key
        	#cat("Address:", address, "\n")
        	#cat("Private Key:", private_key, "\n")
	#}
}

##########################
### Endpoint testing
##########################

#print("fetching contract data from the API")
#itp_api(endpoint="getContract",params=list(coin="WBTC",network="optimism"))

#print("fetching pool compositon from the API")
#itp_api(endpoint="poolComposition",params=list(pool="0x31e109968aa38542c4d9efb9a2daa34b442efa44",network="polygon",protocol="dhedge")) 

#print("creating new wallet")
#result = itp_api(endpoint="createGasWallet",params=list())

#print(result)
#print(isValidApiKey(network="polygon",protocol="dhedge",pool="myPool",apiKey="79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688"))

#result = itp_api(endpoint="linkGasWallet",params=list(network="polygon",protocol="dhedge",pool="0x31e109968aa38542c4d9efb9a2daa34b442efa44",wallet=result$address,apiKey=result$apiKey))
#print(result)

apiKey = "79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688"
pool="0x31e109968aa38542c4d9efb9a2daa34b442efa44"
wallet = "0x1A63a920d6409224cdB5Efcdf625B137eEAD3554"
network = "polygon"
protocol= "dhedge"

print("linking gas wallet")
itp_api(endpoint="linkGasWallet",params=list(network=network,protocol=protocol,pool=pool,wallet=wallet,apiKey=apiKey))
 
#print("setting allocations")
#itp_api(endpoint="setAllocations",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool,assets="WBTC-WETH",allocations="50-50",upper_thresholds="10-10",lower_thresholds="10-10")) 

#print("getting allocations")
#itp_api(endpoint="getAllocations",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool))

#print("getting allocations with incomplete parameters")
#itp_api(endpoint="getAllocations",params=list())

print("setting side")
itp_api(endpoint="setBot",params=list(apiKey=apiKey,protocol=protocol,network=network,pool=pool,pair="BTC-USDC",side="neutral",max_usd=500,slippage=1,threshold=10,share=100,platform="uniswapV3"))

print("unlinking gas wallet")
itp_api(endpoint="unlinkGasWallet",params=list(network=network,protocol=protocol,pool=pool,apiKey=apiKey))
