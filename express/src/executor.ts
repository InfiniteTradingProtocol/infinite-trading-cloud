import { ethers } from "ethers";
import axios from "axios";
//import dotenv from "dotenv";
require("dotenv").config({ path: '../.env' });

const infuraApiKey = process.env.INFURA_PROJECT_ID;
const provider = new ethers.providers.JsonRpcProvider(`https://optimism-mainnet.infura.io/v3/${infuraApiKey}`);
//const infuraApiKey = process.env.INFURA_PROJECT_ID;
//const provider = new ethers.providers.JsonRpcProvider('http://[2a01:240:ad00:2100:3:a883:1053:8fe1]:8545/')

console.log("Private Key:", process.env.PRIVATE_KEY!); // Make sure this is not undefined
const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

// Staking contract as an example
const contractAddress = "0x23371aEEaF8718955C93aEC726b3CAFC772B9E37";

// Etherscan API key from .env
const etherscanApiKey = process.env.etherscan_optimism;

async function getContractAbiAndCode() {
    // Fetch ABI from Etherscan
    const abiResponse = await axios.get(`https://api-optimistic.etherscan.io/api?module=contract&action=getabi&address=${contractAddress}&apikey=${etherscanApiKey}`);
    const abi = JSON.parse(abiResponse.data.result);
    if (!abi) {
        console.log("ABI not found for this contract or contract is not verified.");
        return;
    }
    const contract = new ethers.Contract(contractAddress, abi, provider);
    const contractWithSigner = new ethers.Contract(contractAddress, abi, signer);
    // List all contract functions
    const contractFunctions = Object.keys(contract.interface.functions);
    console.log("Functions in the Contract:");
    console.log(contractFunctions);
    // Get the contract code (source code)
    const sourceCodeResponse = await axios.get(`https://api-optimistic.etherscan.io/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${etherscanApiKey}`);
    let sourceCode = sourceCodeResponse.data.result[0].SourceCode;
    // Decode URI components if needed
    sourceCode = decodeURIComponent(sourceCode);
    // Check if it's a JSON-encoded string
    try {
    	sourceCode = JSON.parse(sourceCode);
    } catch (error) {
            // Not JSON, ignore error
    }
    // Output the formatted source code
    console.log("Verified Source Code:");
    console.log(sourceCode);
    // Check if source code is available and verified
    if (sourceCode === "") { 
	    console.log("Source code is not verified or available.");
    } else { console.log("Verified Source Code:"); console.log(sourceCode); }
    try {
        // Assume the contract has a function named `getDetails()`
        const details = await contractWithSigner.rewardsLeft();
        // const result = await contract.someFunction(param1, param2);
    } catch (error) { console.error("Error calling contract function:", error); }
}
async function getContractAbiAndCode2() {
    try {
        const abiResponse = await axios.get(`https://api-optimistic.etherscan.io/api?module=contract&action=getabi&address=${contractAddress}&apikey=${etherscanApiKey}`);
        const abi = JSON.parse(abiResponse.data.result);
        
        if (!abi) {
            console.log("ABI not found for this contract or contract is not verified.");
            return;
        }
        
        const contract = new ethers.Contract(contractAddress, abi, provider);
        const contractWithSigner = new ethers.Contract(contractAddress, abi, signer); 
        const contractFunctions = Object.keys(contract.interface.functions);

        console.log("Functions in the Contract:", contractFunctions);
        
        const sourceCodeResponse = await axios.get(`https://api-optimistic.etherscan.io/api?module=contract&action=getsourcecode&address=${contractAddress}&apikey=${etherscanApiKey}`);
        let sourceCode = sourceCodeResponse.data.result[0].SourceCode;
        let content;
	
	//######################
	//
	// here i need to fetch the list of executable functions.
	// this list is obtained by invoking in this contract the following function:
	// executableFunctions()
	// after obtaining this list, I need to 
	// iterate over all executable functions f1,..., fn.
	// for each function on the list, invoke the requireExeuction(f1),...,requireExecution(fn)
	// store the list of functions that requires execution, discard the rest. r1,...,rk (list of functions that requires execution)
	// iterate over the list of functions that requires execution
	// simulate(execute(r1),...,execute(rk)); check if those are not malicious.
	// execute(r1), ..., execute(rk)
	//
	//######################

	contractFunctions.forEach((func) => {
		console.log("function name")
		console.log(func);
           	//check if function name is the list of executable functions
	        //	
		// Use bracket notation to invoke the function dynamically
    		contractWithSigner[func]()
        		.then(result => { console.log(`Result of ${func}:`, result);})
        		.catch(error => { console.error(`Error invoking ${func}:`, error);});
	});
        //const functions = await contractWithSigner.rewardsLeft();
        //console.log("Rewards function from the contract:", functions);
    } catch (error) {
        console.error("Error fetching contract details:", error);
    }
}

//  fetch from the registry the list of executable smart contracts;
//  fetch the smart contract code and fetch the list of executable functions
//  validate if the functions are executable or not and return the list of those who are.
//  execute the executable function in the contract.

// use the pim pim contract as the first one.

getContractAbiAndCode2().catch(error => { console.error("Error fetching contract details:", error); });

