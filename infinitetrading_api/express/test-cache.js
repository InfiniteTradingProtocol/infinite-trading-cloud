const { Network } = require("@dhedge/v2-sdk");
const { checkContractsWhitelist } = require("./build/src/utils/vault-guard-cache");

const DEX_ROUTERS = {
    "1inch": "0x1111111254EEB25477B68fb85Ed929f73A960582",
    "kyberswap": "0x6131B5fae19EA4f9D964eAc0408E4408b66337b5",
    "uniswapV3": "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
};

async function test() {
    console.log("Testing vault guard cache...");

    // Use a real vault address from Optimism
    const vaultAddress = "0xb3daeb95b1db64fc0533dbe67c8b7dca04b1781e";

    const whitelisted = await checkContractsWhitelist(
        vaultAddress,
        DEX_ROUTERS,
        Network.OPTIMISM,
        "dex-test"
    );

    console.log("Whitelisted DEXs:", whitelisted);
    process.exit(0);
}

test().catch(err => {
    console.error("Error:", err);
    process.exit(1);
});
