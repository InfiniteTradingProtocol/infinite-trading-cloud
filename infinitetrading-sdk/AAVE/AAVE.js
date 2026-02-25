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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAaveV3HealthFactor = getAaveV3HealthFactor;
const ethers_1 = require("ethers");
const index_1 = require("../index");
const dotenv = __importStar(require("dotenv"));
const path_1 = __importDefault(require("path"));
dotenv.config({ path: path_1.default.resolve(__dirname, "../.env") });
const apiKey = process.env.INFURA_PROJECT_ID;
//npm add ethers @bgd-labs/aave-address-book
const aave_address_book_1 = require("@bgd-labs/aave-address-book");
const providersByChainId = {
    1: aave_address_book_1.AaveV3Ethereum.POOL_ADDRESSES_PROVIDER,
    10: aave_address_book_1.AaveV3Optimism.POOL_ADDRESSES_PROVIDER,
    137: aave_address_book_1.AaveV3Polygon.POOL_ADDRESSES_PROVIDER,
    42161: aave_address_book_1.AaveV3Arbitrum.POOL_ADDRESSES_PROVIDER,
    8453: aave_address_book_1.AaveV3Base.POOL_ADDRESSES_PROVIDER,
    534352: aave_address_book_1.AaveV3Scroll.POOL_ADDRESSES_PROVIDER,
    // add others from the package as needed
};
const IAddressesProviderAbi = [
    "function getPool() external view returns (address)",
];
const IPoolAbi = [
    "function getUserAccountData(address user) external view returns (uint256 totalCollateralBase,uint256 totalDebtBase,uint256 availableBorrowsBase,uint256 currentLiquidationThreshold,uint256 ltv,uint256 healthFactor)",
];
async function getAaveV3HealthFactor(userAddress, network, provider, apiKey) {
    const rpc_provider = new ethers_1.ethers.JsonRpcProvider((0, index_1.rpc)(network, provider, apiKey));
    const { chainId } = await rpc_provider.getNetwork();
    const providerAddress = providersByChainId[Number(chainId)];
    if (!providerAddress) {
        throw new Error(`Chain ${chainId} not in mapping. Use Option B with a PoolAddressesProvider address.`);
    }
    const addressesProvider = new ethers_1.ethers.Contract(providerAddress, IAddressesProviderAbi, rpc_provider);
    const poolAddress = await addressesProvider.getPool();
    const pool = new ethers_1.ethers.Contract(poolAddress, IPoolAbi, rpc_provider);
    const data = await pool.getUserAccountData(userAddress);
    // healthFactor is a RAY (1e18)
    const healthFactor = Number(ethers_1.ethers.formatUnits(data.healthFactor, 18));
    return {
        //chainId: Number(chainId),
        //poolAddress,
        healthFactor,
        //raw: data,
    };
}
// Example:
(async () => {
    const out = await getAaveV3HealthFactor("0xe51af0ba747b9c464057b9099040f4df0b29a7de", "optimism", "infura", apiKey);
    console.log(out);
})();
