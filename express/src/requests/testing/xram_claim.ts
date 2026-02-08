import { Dhedge, Dapp, Network, ethers } from "@dhedge/v2-sdk";

                                                         
const privateKey = "df4730a2cd828b96f7a65214e93168c00d3654a526f664d8152302467c892898";
const providerUrl = "https://arbitrum-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a"

const provider = new ethers.providers.JsonRpcProvider(providerUrl);
const walletWithProvider = new ethers.Wallet(privateKey, provider);

const dhedge = new Dhedge(walletWithProvider, Network.ARBITRUM);
const poolAddress = "0x37acdfc02b78b53c9a0e21a58746cc71e23a8f05"
const pool = await dhedge.loadPool(poolAddress)

const tx = await pool.claimFees(Dapp.RAMSES, "0xf1a5444a7ed5f24962a118512b076a015b0e6c0b")

//const poolAddress = "YOUR_POOL_ADDRESS"
//const pool = await dhedge.loadPool(poolAddress)

