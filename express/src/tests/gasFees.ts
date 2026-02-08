const axios = require('axios');
require("dotenv").config();
async function getGasFees(network) {
    let id;
    let apiKey;
    let apiSecret;

    switch (network) {
        case 'optimism':
            id = 10;
            //apiKey = process.env.INFURA_PROJECT_ID;
            //apiSecret = process.env.INFURA_SECRET;
	    //console.log(process.env.INFURA_PROJECT_ID);
	    //console.log(process.env.INFURA_SECRET);
            apiKey = 'd18c6d8db1024751a822f8b8b208737a'
	    apiSecret = '2fe8d48af4104bc78faf90ae71887455'
	    break;
        // Add more cases for other networks if needed
        default:
            throw new Error('Unsupported network');
    }

    const endpoint = `https://gas.api.infura.io/networks/${id}/baseFeeHistory`;

    try {
        const response = await axios.get(endpoint, {
            auth: {
                username: apiKey,
                password: apiSecret
            }
        });
        return response.data;
    } catch (error) {
        throw new Error('Failed to fetch gas fees');
    }
}
async function getEstimatedBaseFee(network) {
     try { 
	     const data = await getGasFees(network);
     	     return(data.estimatedBaseFee); // Handle the gas fee data here
     }
     catch (error) {
        throw new Error('Failed to get estimated base fee: ' + error.message);
    }
}

//getEstimatedBaseFee('optimism')
//   .then(data => {
//	   console.log(data);
//   }
//)
//   .catch(error => {
//	   console.log(error.message)
//   });

// Example usage
getGasFees('optimism')
    .then(data => {
        console.log(data); // Handle the gas fee data here
    }
)
    .catch(error => {
        console.error(error.message); // Handle error
    });

