"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.lastPrice = lastPrice;
exports.liquidate = liquidate;
const ethers_1 = require("ethers");
const index_1 = require("../index");
const dotenv = __importStar(require("dotenv"));
dotenv.config();
const INFURA_KEY = process.env.INFURA_PROJECT_ID;
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
function formatTokenAmount(amount, decimals) {
    const TEN = BigInt(10);
    const divisor = TEN ** BigInt(decimals);
    const integerPart = amount / divisor;
    const fractionalPart = amount % divisor;
    const formattedFractional = fractionalPart.toString().padStart(decimals, '0'); // Ensure leading zeros are preserved
    return `${integerPart}.${formattedFractional}`;
}
async function lastEGGSPrice(network, provider, apiKey) {
    try {
        const rpc_provider = new ethers_1.ethers.JsonRpcProvider((0, index_1.rpc)(network, provider, apiKey));
        const signer = new ethers_1.ethers.Wallet(process.env.PRIVATE_KEY, rpc_provider);
        // Initialize the contract
        let EGGS_ADDRESS;
        switch (network) {
            case "base":
                EGGS_ADDRESS = "0xddbabe113c376f51e5817242871879353098c296";
                break;
            default:
                throw new Error("Unsupported network specified.");
        }
        const contract = new ethers_1.ethers.Contract(EGGS_ADDRESS, ABI_JSON, signer);
        const result = await contract.lastPrice();
        const decimals = 18;
        const formattedResult = formatTokenAmount(BigInt(result.toString()), decimals);
        return { success: true, data: formattedResult };
        //return { success: true, data: "test" };
    }
    catch (error) {
        console.error("Error executing lastPrice");
        return { success: false, error: "lastPrice not executed" };
    }
}
async function liquidateEGGS(network, provider, apiKey) {
    try {
        const rpc_provider = new ethers_1.ethers.JsonRpcProvider((0, index_1.rpc)(network, provider, apiKey));
        const signer = new ethers_1.ethers.Wallet(process.env.PRIVATE_KEY, rpc_provider);
        // Initialize the contract
        let EGGS_ADDRESS;
        switch (network) {
            case "base":
                EGGS_ADDRESS = "0xddbabe113c376f51e5817242871879353098c296";
                break;
            default:
                throw new Error("Unsupported network specified.");
        }
        const contract = new ethers_1.ethers.Contract(EGGS_ADDRESS, ABI_JSON, signer);
        const tx = await contract.liquidate();
        await tx.wait();
        console.log("Transaction successful:", tx.hash);
        return { success: true, data: tx.hash };
        //return { success: true, data: "test" };
    }
    catch (error) {
        console.error("Error executing liquidate");
        return { success: false, error: "liquidate not executed" };
    }
}
async function lastPrice() {
    const network = "base"; // Example network
    const provider = "infura";
    const apiKey = INFURA_KEY;
    const result = await lastEGGSPrice(network, provider, apiKey);
    if (result.success) {
        console.log("Success result:", result.data);
    }
    else {
        console.error("Failed to fetch price data:", result.error);
    }
}
async function liquidate() {
    const network = "base"; // Example network
    const provider = "infura";
    const apiKey = INFURA_KEY;
    const result = await liquidateEGGS(network, provider, apiKey);
    if (result.success) {
        console.log("Success result:", result.data);
    }
    else {
        console.error("Failed to fetch pool data:", result.error);
    }
}
liquidate();
lastPrice();
