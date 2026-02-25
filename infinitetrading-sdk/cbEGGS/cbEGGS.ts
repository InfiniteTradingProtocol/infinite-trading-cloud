import { ethers, Contract } from "ethers";
import axios from "axios";
import { rpc,Network } from "../index";
import * as dotenv from "dotenv";

dotenv.config();

const INFURA_KEY =  process.env.INFURA_PROJECT_ID!;
const ABI_JSON = [
    {
        "inputs": [],
        "name": "liquidate",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function"
    },
    {
        "inputs": [],
        "name": "lastPrice",
        "outputs": [
            {
                "internalType": "uint256",
                "name": "",
                "type": "uint256"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    }
];

const infuraApiKey = process.env.INFURA_PROJECT_ID;

function formatTokenAmount(amount: bigint, decimals: number): string {
    const TEN: bigint = BigInt(10);
    const divisor: bigint = TEN ** BigInt(decimals);
    const integerPart = amount / divisor;
    const fractionalPart = amount % divisor;
    const formattedFractional = fractionalPart.toString().padStart(decimals, '0'); // Ensure leading zeros are preserved
    return `${integerPart}.${formattedFractional}`;
}

async function lastEGGSPrice(network: `${Network}`, provider: string | null, apiKey: string | null) {
    try {	
	const rpc_provider = new ethers.JsonRpcProvider(rpc(network,provider,apiKey));
	const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, rpc_provider);
        // Initialize the contract
        let EGGS_ADDRESS: string;
        switch (network) {
            case "base":
                EGGS_ADDRESS = "0xddbabe113c376f51e5817242871879353098c296";
                break;
            default:
                throw new Error("Unsupported network specified.");
        }
	const contract = new ethers.Contract(EGGS_ADDRESS, ABI_JSON, signer);
	const result = await contract.lastPrice();
	const decimals = 18;
        const formattedResult = formatTokenAmount(BigInt(result.toString()), decimals);
        return { success: true, data:  formattedResult };
	//return { success: true, data: "test" };
    } catch (error: any) {
        console.error("Error executing lastPrice");
        return { success: false, error: "lastPrice not executed" };
    }
}
async function liquidateEGGS(network: `${Network}`, provider: string | null, apiKey: string | null) {
    try {
        const rpc_provider = new ethers.JsonRpcProvider(rpc(network,provider,apiKey));
        const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, rpc_provider);
        // Initialize the contract
        let EGGS_ADDRESS: string;
        switch (network) {
            case "base":
                EGGS_ADDRESS = "0xddbabe113c376f51e5817242871879353098c296";
                break;
            default:
                throw new Error("Unsupported network specified.");
        }
        const contract = new ethers.Contract(EGGS_ADDRESS, ABI_JSON, signer);
        const tx = await contract.liquidate();
        await tx.wait();
        console.log("Transaction successful:", tx.hash);
        return { success: true, data: tx.hash };
        //return { success: true, data: "test" };
    } catch (error: any) {
        console.error("Error executing liquidate");
        return { success: false, error: "liquidate not executed" };
    }
}
export async function lastPrice() {
    const network = "base";  // Example network
    const provider = "infura";
    const apiKey = INFURA_KEY;

    const result = await lastEGGSPrice(network as `${Network}`, provider, apiKey);
    if (result.success) {
        console.log("Success result:", result.data);
    } else {
        console.error("Failed to fetch price data:", result.error);
    }
}

export async function liquidate() {
    const network = "base";  // Example network
    const provider = "infura";
    const apiKey = INFURA_KEY;

    const result = await liquidateEGGS(network as `${Network}`, provider, apiKey);
    if (result.success) {
        console.log("Success result:", result.data);
    } else {
        console.error("Failed to fetch pool data:", result.error);
    }
}
liquidate();
lastPrice();

