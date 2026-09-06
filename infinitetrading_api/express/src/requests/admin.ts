import { Network, SupportedAsset } from "@dhedge/v2-sdk";
import { Router } from "express";
import { ethers, BigNumber } from "ethers";

const adminRouter = Router();
import { Request, Response } from "express";
import { dhedge, dhedgev2 } from "../dhedge";
import { walletv2, generateApiToken, getWalletAddressFromToken } from "../walletv2";
import { apiPayment, feeData, txFees } from "../txFees";
import { rpc, getAllRpcProviders } from "../rpc";
import { createRetryProviderWithFailover } from "../utils/RetryProvider";

// Multicall3 contract address (same on all chains)
const MULTICALL3_ADDRESS = "0xcA11bde05977b3631167028862bE2a173976CA11";

// Multicall3 ABI (only aggregate3 function)
const MULTICALL3_ABI = [
  "function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) returns (tuple(bool success, bytes returnData)[] returnData)"
];

// PoolManagerLogic ABI for getFundComposition
const POOL_MANAGER_ABI = [
  "function poolManagerLogic() view returns (address)",
  "function getFundComposition() view returns (tuple(address asset, bool isDeposit)[] assets, uint256[] balances, uint256[] rates)"
];

//import { Mutex } from "async-mutex";

//const walletLocks = new Map<string, Mutex>();

//function getLockForKey(apiKey: string) {
//  if (!walletLocks.has(apiKey)) walletLocks.set(apiKey, new Mutex());
//  return walletLocks.get(apiKey)!;
//}

require("dotenv").config({ path: '../../.env' });
const ALCHEMY_BALANCES_KEY = process.env.ALCHEMY_BALANCES_KEY as string;

// ── Signature verification cache ─────────────────────────────────────────────
// Caches successful EIP-1271 results so repeated calls (e.g. every page load)
// don't re-do expensive multi-network RPC calls. TTL = 1 hour.
interface SigCacheEntry { isValid: boolean; method: string; network?: string; ts: number; }
const sigCache = new Map<string, SigCacheEntry>();
const SIG_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
function getSigCacheKey(signature: string, expectedAddress: string) {
  return `${signature.toLowerCase()}:${expectedAddress.toLowerCase()}`;
}
function getCachedSig(signature: string, expectedAddress: string): SigCacheEntry | null {
  const key = getSigCacheKey(signature, expectedAddress);
  const entry = sigCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.ts > SIG_CACHE_TTL_MS) { sigCache.delete(key); return null; }
  return entry;
}
function setCachedSig(signature: string, expectedAddress: string, result: Omit<SigCacheEntry, 'ts'>) {
  sigCache.set(getSigCacheKey(signature, expectedAddress), { ...result, ts: Date.now() });
}

// Error response helper
function sendErrorResponse(res: Response, statusCode: number, errorCode: number, message: string, errorType: string, details?: any) {
  const response: any = {
    status: "fail",
    status_code: errorCode,
    message: message,
    error_type: errorType
  };
  if (details) {
    response.details = details;
  }
  res.status(statusCode).send(response);
}

// Multicall helper to batch getFundComposition calls
async function batchGetPoolCompositions(poolAddresses: string[], provider: ethers.providers.Provider) {
  const multicall = new ethers.Contract(MULTICALL3_ADDRESS, MULTICALL3_ABI, provider);
  const poolInterface = new ethers.utils.Interface(POOL_MANAGER_ABI);

  // First, get all poolManagerLogic addresses
  const managerCalls = poolAddresses.map(poolAddress => ({
    target: poolAddress,
    allowFailure: true,
    callData: poolInterface.encodeFunctionData("poolManagerLogic")
  }));

  const managerResults = await multicall.callStatic.aggregate3(managerCalls);

  // Build getFundComposition calls for successful manager lookups
  const compositionCalls: any[] = [];
  const poolIndexMap: number[] = []; // Maps composition call index to original pool index

  managerResults.forEach((result: any, index: number) => {
    if (result.success) {
      try {
        const managerAddress = poolInterface.decodeFunctionResult("poolManagerLogic", result.returnData)[0];
        compositionCalls.push({
          target: managerAddress,
          allowFailure: true,
          callData: poolInterface.encodeFunctionData("getFundComposition")
        });
        poolIndexMap.push(index);
      } catch (err) {
        // Skip if decode fails
      }
    }
  });

  // Execute all getFundComposition calls in one multicall
  const compositionResults = await multicall.callStatic.aggregate3(compositionCalls);

  // Parse results and map back to original pool addresses
  const finalResults = poolAddresses.map((poolAddress, index) => {
    const compositionIndex = poolIndexMap.indexOf(index);

    if (compositionIndex === -1 || !compositionResults[compositionIndex].success) {
      return {
        pool: poolAddress,
        success: false,
        error: "Failed to fetch composition"
      };
    }

    try {
      const decoded = poolInterface.decodeFunctionResult(
        "getFundComposition",
        compositionResults[compositionIndex].returnData
      );

      const assets = decoded[0];
      const balances = decoded[1];
      const rates = decoded[2];

      const composition = assets.map((asset: any, i: number) => ({
        asset: asset.asset,
        isDeposit: asset.isDeposit,
        balance: balances[i],
        rate: rates[i]
      }));

      return {
        pool: poolAddress,
        success: true,
        composition
      };
    } catch (err) {
      return {
        pool: poolAddress,
        success: false,
        error: err instanceof Error ? err.message : String(err)
      };
    }
  });

  return finalResults;
}

adminRouter.post("/createWallet", async (req: Request, res: Response) => {
  try {
    const wallet = await ethers.Wallet.createRandom();
    res.status(200).send({ status: "success", address: wallet.address, privateKey: wallet.privateKey });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3001, message, "create_wallet_failed");
  }
});

adminRouter.post("/verifySignature", async (req: Request, res: Response) => {
  const { message, signature, expectedAddress, network } = req.body;

  if (!message || !signature || !expectedAddress) {
    return res.status(400).send({
      status: "fail",
      msg: "Missing message, signature, or expectedAddress",
    });
  }

  // ── Cache check — skip all RPC calls if we've seen this sig before ─────────
  const cached = getCachedSig(signature, expectedAddress);
  if (cached) {
    return res.status(200).send({ status: "success", isValid: cached.isValid, recoveredAddress: cached.isValid ? expectedAddress : null, method: cached.method + "_cached", network: cached.network });
  }

  // ── Step 1: Try EOA recovery (works for regular wallets) ──────────────────
  try {
    const recoveredAddress = ethers.utils.verifyMessage(message, signature);
    if (recoveredAddress.toLowerCase() === expectedAddress.toLowerCase()) {
      setCachedSig(signature, expectedAddress, { isValid: true, method: "eoa" });
      return res.status(200).send({ status: "success", isValid: true, recoveredAddress, method: "eoa" });
    }
  } catch (_) {
    // signature may be non-standard (Safe packed) — fall through to EIP-1271
  }

  // ── Step 2: EIP-1271 — contract signature (Safe multisig) ─────────────────
  // Try the supplied network first, then fall back to all supported networks.
  // This handles the case where the user switches to a different network on the
  // frontend but their Safe only exists on one specific chain.
  const EIP1271_MAGIC = "0x1626ba7e";
  const iface = new ethers.utils.Interface([
    "function isValidSignature(bytes32 hash, bytes signature) view returns (bytes4)"
  ]);
  const messageHash = ethers.utils.hashMessage(message);

  // Build ordered list of networks to try: supplied network first, then rest
  const ALL_NETWORKS: Network[] = [Network.BASE, Network.OPTIMISM, Network.ARBITRUM, Network.POLYGON, Network.ETHEREUM];
  const suppliedNet = network ? (network as string).toLowerCase() as Network : null;
  const networksToTry = suppliedNet
    ? [suppliedNet, ...ALL_NETWORKS.filter(n => n !== suppliedNet)]
    : ALL_NETWORKS;

  for (const net of networksToTry) {
    try {
      const provider = createRetryProviderWithFailover(getAllRpcProviders(net));
      const callData = iface.encodeFunctionData("isValidSignature", [messageHash, signature]);
      const result = await provider.call({ to: expectedAddress, data: callData });
      const returnedMagic = result.slice(0, 10).toLowerCase();
      if (returnedMagic === EIP1271_MAGIC) {
        setCachedSig(signature, expectedAddress, { isValid: true, method: "eip1271", network: net });
        return res.status(200).send({ status: "success", isValid: true, recoveredAddress: expectedAddress, method: "eip1271", network: net });
      }
    } catch (_) {
      // This network failed — try next
    }
  }

  // All networks exhausted — not a valid Safe signature either
  return res.status(200).send({
    status: "success", isValid: false, recoveredAddress: null, method: "eip1271_failed",
    detail: "Signature did not match via EOA or EIP-1271 on any supported network"
  });
});

adminRouter.post("/createPool", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = null; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key);
      pool = await dHedge.createPool(req.body.managerName, req.body.poolName, req.body.symbol, req.body.supportedAssets as unknown as SupportedAsset[], Number(req.body.fee));
    }
    else { pool = await dhedge(network, manager).createPool(req.body.managerName, req.body.poolName, req.body.symbol, req.body.supportedAssets as unknown as SupportedAsset[], Number(req.body.fee)); }
    res.status(200).send({
      status: "success",
      msg: pool.address,
    });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3002, message, "create_pool_failed");
  }
});

adminRouter.get("/getPool", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = null; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    res.status(200).send({ status: "success", msg: pool });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3003, message, "get_pool_failed");
  }
});

adminRouter.get("/getSummary", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = null; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    res.status(200).send({ status: "success", msg: pool });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3004, message, "get_summary_failed");
  }
});

// ── POST /getApiKey ──────────────────────────────────────────────────────────
// Accepts: privateKey (query param or JSON body)
// Returns: { status: "success", apiKey: "<uuid>" }
// Called by R plumber's getApiKeyHandler (replaces local secure_encrypt)
adminRouter.get("/getApiKey", async (req: Request, res: Response) => {
  try {
    const privateKey = (req.query.privateKey as string) || (req.body?.privateKey as string);
    if (!privateKey) return sendErrorResponse(res, 400, 3020, 'Missing privateKey', 'get_api_key_failed');
    const token = await generateApiToken(privateKey);
    return res.status(200).send({ status: 'success', status_code: 200, apiKey: token });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3020, message, 'get_api_key_failed');
  }
});

// ── GET /getWallet ────────────────────────────────────────────────────────────
// UUID token  → DB lookup (wallet_address stored at token-generation time, no decrypt)
adminRouter.get("/getWallet", async (req: Request, res: Response) => {
  try {
    const apiKey = req.query.apiKey as string;
    if (!apiKey) return sendErrorResponse(res, 400, 3005, 'Missing apiKey', 'get_wallet_failed');

    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (UUID_RE.test(apiKey)) {
      // New scheme: resolve from DB — no private key decryption needed
      const address = await getWalletAddressFromToken(apiKey);
      if (!address) return sendErrorResponse(res, 404, 3005, 'Token not found', 'get_wallet_failed');
      return res.status(200).send({ status: 'success', msg: address });
    }

    // Legacy hex-format keys are no longer supported. Use createGasWallet to get a UUID token.
    return sendErrorResponse(res, 400, 3005, 'Invalid token format — only UUID tokens are supported', 'get_wallet_failed');
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3005, message, 'get_wallet_failed');
  }
});

// Raw SDK-shape composition (asset, isDeposit, balance{BigNumber}, rate{BigNumber}).
// Used internally by tradeEngine.ts's poolComp() enrichment and by trade.ts.
// The public /poolComposition (enriched, R-parity shape) lives in
// requests/poolCompositionEnriched.ts.
adminRouter.get("/poolCompositionRaw", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge; let apiKey = 'none'; let provider = 'alchemy'; let key = ALCHEMY_BALANCES_KEY;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    console.log(`📌 /poolComposition | 🌐 ${network} | 📌 ${poolAddress} | 🌐 ${provider} | 🗝️ ${key ?? "N/A"}`);
    const composition = await pool.getComposition();
    res.status(200).send({ status: "success", msg: composition });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3006, message, "get_composition_failed");
  }
});

// Batch endpoint to fetch multiple pool compositions in one call
adminRouter.post("/poolCompositionBatch", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;

    const poolAddresses = req.body.pools as string[]; // Array of pool addresses
    if (!poolAddresses || !Array.isArray(poolAddresses) || poolAddresses.length === 0) {
      return sendErrorResponse(res, 400, 3008, "pools array is required in request body", "batch_composition_invalid_input");
    }

    // Limit batch size to avoid rate limiting and timeouts
    const MAX_BATCH_SIZE = 50;
    if (poolAddresses.length > MAX_BATCH_SIZE) {
      return sendErrorResponse(res, 400, 3011, `Batch size exceeds maximum of ${MAX_BATCH_SIZE} pools. Received ${poolAddresses.length}`, "batch_size_exceeded");
    }

    let providerName = 'alchemy';
    let key = ALCHEMY_BALANCES_KEY;

    if (req.query.provider) { providerName = req.query.provider as string; }
    if (req.query.providerKey) { key = req.query.providerKey as string; }

    // Get ethers provider for multicall
    const rpcUrl = rpc(network, providerName, key);
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

    console.log(`📦 /poolCompositionBatch (MULTICALL) | 🌐 ${network} | 📊 ${poolAddresses.length} pools | 🌐 ${providerName}`);

    // Use multicall to fetch all compositions in ONE RPC call
    const results = await batchGetPoolCompositions(poolAddresses, provider);

    res.status(200).send({
      status: "success",
      count: results.length,
      results
    });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3009, message, "batch_composition_failed");
  }
});

adminRouter.get("/getManagerFee", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = 'infura'; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    const fees = await pool.getAvailableManagerFee();
    res.status(200).send({ status: "success", msg: fees });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3007, message, "get_manager_fee_failed");
  }
});

adminRouter.get("/mintManagerFee", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null; let provider = 'infura'; let key = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    let estimatedGas;
    estimatedGas = await pool.mintManagerFee(null, true);
    console.log(estimatedGas)
    const txOptions = await txFees(network, provider, key, estimatedGas);
    const tx = await pool.mintManagerFee(txOptions, false);
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      console.log("Sending API payment");
      apiPayment(network, apiKey, tx, provider, key, null)
    }
    res.status(200).send({ status: "success", msg: tx });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3008, message, "mint_manager_fee_failed");
  }
});
adminRouter.post("/changeAssets", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = null; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress); }
    const tx = await pool.changeAssets(req.body.assets);
    res.status(200).send({ status: "success", msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3009, message, "change_assets_failed");
  }
});

adminRouter.post("/setTrader", async (req: Request, res: Response) => {
  try {
    let network = Network.POLYGON;
    if (req.query.network) network = req.query.network as Network;
    const poolAddress = req.query.pool as string;
    let pool; let dHedge;
    let manager = null;
    if (req.query.manager) { manager = req.query.manager as string; }
    if (req.query.apiKey) {
      const apiKey = req.query.apiKey as string;
      let provider = null; let key = null;
      if (req.query.provider) { provider = req.query.provider as string; }
      if (req.query.providerKey) { key = req.query.providerKey as string; }
      dHedge = await dhedgev2(network, apiKey, provider, key)
      pool = await dHedge.loadPool(poolAddress);
    }
    else { pool = await dhedge(network, manager).loadPool(poolAddress) }
    const tx = await pool.setTrader(req.body.traderAccount);
    res.status(200).send({ status: "success", status_code: 200, msg: tx.hash });
  } catch (err) {
    const message = (err instanceof Error) ? err.message : String(err);
    sendErrorResponse(res, 400, 3010, message, "set_trader_failed");
  }
});

export default adminRouter;
