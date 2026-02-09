import express from "express";
import { Network } from "@dhedge/v2-sdk";
import {
  getEthPriceUSD,
  getNativeTokenPriceUSD,
  calculateApiFeeInNativeToken,
  calculateApiFeeInWei,
  getActionPriceUSD,
  getAllPricing
} from "../apiPricing";

const router = express.Router();

/**
 * GET /api/pricing/eth-price
 * Get current ETH price from Redis
 */
router.get('/eth-price', async (req, res) => {
  try {
    const price = await getEthPriceUSD();
    
    if (price === null) {
      return res.status(503).json({
        error: 'ETH price unavailable',
        message: 'Could not fetch ETH price from Redis'
      });
    }
    
    res.json({
      price: price,
      currency: 'USD',
      source: 'Redis (coinbase_ETH-USD)'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

/**
 * GET /api/pricing/token-price/:network
 * Get native token price for a specific network
 */
router.get('/token-price/:network', async (req, res) => {
  try {
    const network = req.params.network as Network;
    const price = await getNativeTokenPriceUSD(network);
    
    if (price === null) {
      return res.status(503).json({
        error: 'Token price unavailable',
        message: `Could not fetch ${network} token price from Redis`
      });
    }
    
    res.json({
      network: network,
      price: price,
      currency: 'USD',
      token: network === 'polygon' ? 'MATIC/POL' : 'ETH'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

/**
 * GET /api/pricing/calculate-fee/:action/:network
 * Calculate the fee for a specific action on a network
 */
router.get('/calculate-fee/:action/:network', async (req, res) => {
  try {
    const { action, network } = req.params;
    
    const usdPrice = getActionPriceUSD(action);
    const feeInToken = await calculateApiFeeInNativeToken(action, network as Network);
    const feeInWei = await calculateApiFeeInWei(action, network as Network);
    const tokenPrice = await getNativeTokenPriceUSD(network as Network);
    
    if (!feeInToken || !feeInWei || !tokenPrice) {
      return res.status(503).json({
        error: 'Cannot calculate fee',
        message: 'Token price unavailable from Redis'
      });
    }
    
    res.json({
      action: action,
      network: network,
      pricing: {
        usd: usdPrice,
        nativeToken: parseFloat(feeInToken),
        wei: feeInWei.toString()
      },
      tokenPrice: {
        token: network === 'polygon' ? 'MATIC' : 'ETH',
        priceUSD: tokenPrice
      }
    });
  } catch (error) {
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

/**
 * GET /api/pricing/all-actions
 * Get all action prices in USD
 */
router.get('/all-actions', async (req, res) => {
  try {
    const allPricing = getAllPricing();
    const ethPrice = await getEthPriceUSD();
    
    res.json({
      pricingUSD: allPricing,
      currentETHPrice: ethPrice,
      note: 'Prices are in USD and converted to native token based on current market price'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

/**
 * GET /api/pricing/test/:network
 * Test endpoint to see all fees for all actions on a specific network
 */
router.get('/test/:network', async (req, res) => {
  try {
    const network = req.params.network as Network;
    const allPricing = getAllPricing();
    const tokenPrice = await getNativeTokenPriceUSD(network);
    
    if (!tokenPrice) {
      return res.status(503).json({
        error: 'Cannot calculate fees',
        message: 'Token price unavailable from Redis'
      });
    }
    
    const results: any = {};
    
    for (const [action, usdPrice] of Object.entries(allPricing)) {
      const feeInToken = await calculateApiFeeInNativeToken(action, network);
      results[action] = {
        usd: usdPrice,
        nativeToken: feeInToken ? parseFloat(feeInToken) : null
      };
    }
    
    res.json({
      network: network,
      tokenPrice: {
        token: network === 'polygon' ? 'MATIC' : 'ETH',
        priceUSD: tokenPrice
      },
      fees: results
    });
  } catch (error) {
    res.status(500).json({
      error: 'Internal server error',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

export default router;
