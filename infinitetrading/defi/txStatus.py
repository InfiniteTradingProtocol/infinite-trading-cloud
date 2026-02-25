import requests
import json 

#Obtain the URL for each network

def url(network):
    if network == "mainnet" or network == "ethereum":
        api_url = "https://api.etherscan.io/api"
    elif network == "polygon":
        api_url = "https://api.polygonscan.com/api"
    elif network == "optimism":
        api_url = "https://api-optimistic.etherscan.io/api"
    elif network == "arbitrum":
        api_url = "https://api.arbiscan.io/api"
    else:
        raise ValueError("Invalid network parameter. Valid options are 'mainnet', 'polygon', 'optimism', or 'arbitrum'.")
    return api_url

#Obtain the transaction status from the hash and network.

def txStatus(hash, network):
    # Set the Etherscan API endpoint URL based on the network parameter
    api_url = url(network)
    # Set the Etherscan API endpoint parameters
    api_params = {
        "module": "transaction",
        "action": "gettxreceiptstatus",
        "txhash": hash
    }

    # Make the API call to get the transaction status
    api_response = requests.get(api_url, params=api_params)
    api_content = api_response.json()
    print(api_content)
    # Check if the API call was successful
    if api_response.status_code != 200:
        raise ValueError(f"Error: API call failed with status code {api_response.status_code}")

    # Check if the transaction was found
    if api_content["status"] != "1":
        raise ValueError("Error: Transaction not found or invalid transaction hash.")

    # Return the transaction status
    print(api_content)
    status = api_content["result"]["status"]
    if status == '':
        return "Error"
    else:
        status = int(status)
    print(status)
    if network == "mainnet":
        if api_content["result"]["isError"] == "1":
            return "Error"
        elif status == 1:
            return "Success"
        else:
            return "Pending"
    elif network == "polygon":
        if status == "0":
            return "Error"
        elif status == 1:
            return "Success"
        else:
            return "Pending"
    elif network == "optimism": 
        if status == 1:
            return "Success"

status =txStatus("0xdf0ed472202c3ba4efaad2fea60fc860f900c4ab33a84aa15b4dd11d17d61ee5","optimism")
print(status)
