"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.wallet = void 0;
var v2_sdk_1 = require("@dhedge/v2-sdk");
require("dotenv").config({ path: '../.env' });
function rpcURL(network, manager) {
    if (manager === void 0) { manager = null; }
    var provider_key;
    if (manager === null) {
        provider_key = process.env.ALCHEMY_API_KEY;
        if (!provider_key) {
            throw new Error("No ALCHEMY_API_KEY in the .env file found");
        }
    }
    else {
        var provider_keyEnvVarName = "ALCHEMY_API_KEY_".concat(manager);
        provider_key = process.env[provider_keyEnvVarName];
        if (!provider_key) {
            provider_key = process.env.ALCHEMY_API_KEY;
            if (!provider_key) {
                throw new Error("No ALCHEMY_API_KEY in the .env file found");
            }
        }
    }
    switch (network) {
        case 'polygon':
            return "https://polygon-mainnet.g.alchemy.com/v2/".concat(provider_key);
        case 'optimism':
            return "https://opt-mainnet.g.alchemy.com/v2/".concat(provider_key);
        case 'arbitrum':
            return "https://arb-mainnet.g.alchemy.com/v2/".concat(provider_key);
        case 'base':
            return "https://base-mainnet.g.alchemy.com/v2/".concat(provider_key);
        default:
            throw new Error('Network not supported');
    }
}
;
var wallet = function (network, manager) {
    if (manager === void 0) { manager = null; }
    //console.log(url)
    var privateKey;
    if (manager === null) {
        privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) {
            throw Error("No PRIVATE_KEY in the .env file found");
        }
    }
    else {
        var privateKeyEnvVarName = "PRIVATE_KEY_".concat(manager);
        privateKey = process.env[privateKeyEnvVarName];
        if (!privateKey) {
            privateKey = process.env.PRIVATE_KEY;
        }
        if (!privateKey) {
            throw Error("No PRIVATE_KEY in the .env file found");
        }
    }
    var url = rpcURL(network, manager); // Ensure rpcURL is properly imported and used
    //console.log(privateKey)
    return new v2_sdk_1.ethers.Wallet(privateKey, new v2_sdk_1.ethers.providers.JsonRpcProvider(url));
};
exports.wallet = wallet;
