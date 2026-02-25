import { ethers, formatUnits } from "ethers";
import axios from "axios";
import { rpc,Network,getUSDC_Address,formatAmount,formatDate } from "../index";
import { Bribe, Fee, EpochData, ReadableFee, ReadableBribe } from './interfaces';

// VeSugar Contract Address (Optimism)
const LP_SUGAR_ADDRESS = "0x35F233BE126d7D08aB2D65E647E8c379b1FACF39"; // Update if needed
const OP_ORACLE_ADDRESS = "0x395942C2049604a314d39F370Dfb8D87AAC89e16";
import * as dotenv from "dotenv";
dotenv.config({ path: "../.env" });

const ABI_JSON = JSON.parse(process.env.ABI_JSON!);
const ORACLE_ABI_JSON = JSON.parse(process.env.ORACLE_ABI_JSON!);
const infuraApiKey = process.env.INFURA_PROJECT_ID;

// Define the getPrice TypeScript function
export async function getPrice(connectors: string[],network: `${Network}`, provider: string | null, apiKey: string | null): Promise<any> {
    const rpc_provider = new ethers.JsonRpcProvider(rpc(network,provider,apiKey));
    const contract = new ethers.Contract(OP_ORACLE_ADDRESS, ORACLE_ABI_JSON, rpc_provider);
    try {
        const rate = await contract.getManyRatesWithConnectors(1, connectors);
        return formatAmount(rate.toString(),18);
    } catch (error) {
        console.error('Error fetching prices:', error);
        throw new Error('Failed to fetch prices');
    }
}

export async function getPriceUSDC(tokens: string[], network: `${Network}`, provider: string | null, apiKey: string | null): Promise<any> {
    // Append the USDC address to the tokens array
    const connectors = [...tokens, getUSDC_Address(network)];

    // Call the existing getPrice function with the modified list
    return getPrice(connectors, network, provider, apiKey);
} 
async function getPoolData(lpAddress: string,network: `${Network}`, provider: string | null, apiKey: string | null) {
    try {
        if (!ethers.isAddress(lpAddress)) {
            throw new Error("Invalid LP address format.");
        }
	//console.log(network)	
        // Initialize the provider
        //const provider = new ethers.JsonRpcProvider
        //   `https://optimism-mainnet.infura.io/v3/${infuraApiKey}`
        //);
	const rpc_provider = new ethers.JsonRpcProvider(rpc(network,provider,apiKey));

        // Initialize the contract
        let SUGAR_ADDRESS: string;
        switch (network) {
            case "optimism":
                SUGAR_ADDRESS = "0x35F233BE126d7D08aB2D65E647E8c379b1FACF39";
                break;
            case "base":
                SUGAR_ADDRESS = "0x63a73829C74e936C1D2EEbE64164694f16700138";
                break;
            case "fraxtal":
                SUGAR_ADDRESS = "0xB1d0DFFe6260982164B53EdAcD3ccd58B081889d";
                break;
            case "lisk":
                SUGAR_ADDRESS = "0x0F5B7D59690F99f34081E24557f022d06d580BB6";
                break;
            case "mode":
                SUGAR_ADDRESS = "0x8A5e97184E8850064805fAc2427ce7728689De5B";
                break;
            default:
                throw new Error("Unsupported network specified.");
        }
	const contract = new ethers.Contract(SUGAR_ADDRESS, ABI_JSON, rpc_provider);

        // Fetch contract data
        const result = await contract.epochsByAddress(1, 0, lpAddress);

        // Ensure result is iterable
        if (!result || !Array.isArray(result)) {
            throw new Error("Invalid contract data format.");
        }

        // Parse epochs data
        const epochsData = result.map((epoch: any, index: number) => {
            const ts = epoch[0];
            const lp = epoch[1];
            const votes = epoch[2];
            const emissions = epoch[3];

            // Parse bribes and fees safely
            const bribes = (epoch[4] || []).map((item: any, idx: number) => ({
                index: idx,
                token: item[0],
                amount: item[1].toString(),
            }));

            const fees = (epoch[5] || []).map((item: any, idx: number) => ({
                index: idx,
                token: item[0],
                amount: item[1].toString(),
            }));
            return {
                epochIndex: index,
                timestamp: ts.toString(),
                lp: lp,
                votes: votes.toString(),
                emissions: emissions.toString(),
                bribes: bribes,
                fees: fees,
            };
        });
        // Return the structured JSON data
        return { success: true, data: epochsData };
    } catch (error: any) {
        console.error("Error fetching contract data:", error.message);
        return { success: false, error: error.message };
    }
}
// Function to extract and return a flat list of all bribes from the pool data
function getBribesFromPoolData(poolData: { success: boolean; data?: EpochData[] }): Fee[] {
    if (!poolData.success || !poolData.data) {
        console.error("Failed to extract pool data or data is undefined.");
        return [];
    }
    const bribes = poolData.data.flatMap(epoch => epoch.bribes.map((bribe: Bribe) => ({
        ...bribe,
        epochIndex: epoch.epochIndex,
        timestamp: formatDate(epoch.timestamp)
    })));
    return bribes;
}

// Function to extract and return a flat list of all LP fees from the pool data
function getFeesFromPoolData(poolData: { success: boolean; data?: EpochData[] }): Fee[] {
    if (!poolData.success || !poolData.data) {
        console.error("Failed to extract pool data or data is undefined.");
        return [];
    }
    const fees = poolData.data.flatMap(epoch => epoch.fees.map((fee: Fee) => ({
        ...fee,
        epochIndex: epoch.epochIndex,
        timestamp: formatDate(epoch.timestamp),
    })));
    return fees;
}
export function getReadableFees(fees: Fee[]): ReadableFee[] {
    return fees.map(fee => ({
        ...fee,
        readableAmount: formatAmount(fee.amount)  // Formatting the amount and storing in a new property
    }));
}
export function getReadableBribes(bribes: Bribe[]): ReadableBribe[] {
    return bribes.map(bribe => ({
        ...bribe,
        readableAmount: formatAmount(bribe.amount)  // Formatting the amount and storing in a new property
    }));
}

async function exampleUsage() {
    const lpAddress = "0xC04754F8027aBBFe9EeA492C9cC78b66946a07D1";  // Example LP address
    const network = "optimism";  // Example network
    const provider = "infura";
    const apiKey = null;

    const poolData = await getPoolData(lpAddress, network as `${Network}`, provider, apiKey);
    if (poolData.success) {
        const fees = getFeesFromPoolData(poolData);
        const readableFees = getReadableFees(fees);
        console.log("Readable Fees:", readableFees);

        const bribes = getBribesFromPoolData(poolData);
        const readableBribes = getReadableBribes(bribes);
        console.log("Readable Bribes:", readableBribes);
    } else {
        console.error("Failed to fetch pool data:", poolData.error);
    }
}

getPrice(['0x0a7B751FcDBBAA8BB988B9217ad5Fb5cfe7bf7A0', '0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85'],"optimism","infura",null)
     .then(prices => console.log('Prices:', prices))
     .catch(err => console.error(err));

getPriceUSDC(['0x0a7B751FcDBBAA8BB988B9217ad5Fb5cfe7bf7A0'],"optimism","infura",null)
     .then(prices => console.log('Prices:', prices))
     .catch(err => console.error(err));

// create a max bribe function that fetches balances calculate prices and estimate it

// calculateBribes(LP,bribeToken, bribeTokenRoute)

exampleUsage();

//async function run() {
//    const data = await getPoolData("0xC04754F8027aBBFe9EeA492C9cC78b66946a07D1","optimism","infura",null);
//    console.log(data);
//}

//run();
