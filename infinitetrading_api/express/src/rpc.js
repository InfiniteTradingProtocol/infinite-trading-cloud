"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.rpc = rpc;
var v2_sdk_1 = require("@dhedge/v2-sdk");
require("dotenv").config({ path: '../.env' });
function rpc(network, provider, key) {
    if (provider === void 0) { provider = null; }
    if (key === void 0) { key = null; }
    var apiKey;
    var url;
    var word;
    if (provider == null) {
        provider = 'alchemy';
    }
    switch (provider) {
        case 'alchemy':
            if (key == null) {
                apiKey = process.env.ALCHEMY_API_KEY;
                if (!apiKey) {
                    throw new Error("No ALCHEMY_API_KEY in the .env file found");
                }
            }
            else {
                apiKey = key;
            }
            switch (network) {
                case v2_sdk_1.Network.ETHEREUM:
                    word = 'eth';
                    break;
                case v2_sdk_1.Network.ARBITRUM:
                    word = 'arb';
                    break;
                case v2_sdk_1.Network.OPTIMISM:
                    word = 'opt';
                    break;
                case v2_sdk_1.Network.BASE:
                    word = 'base';
                    break;
                case v2_sdk_1.Network.POLYGON:
                    word = 'polygon';
                    break;
                default:
                    word = network;
                    break;
            }
            url = "https://".concat(word, "-mainnet.g.alchemy.com/v2/").concat(apiKey);
            break;
        case 'infura':
            if (key == null) {
                apiKey = process.env.INFURA_PROJECT_ID;
                if (!apiKey) {
                    throw new Error("No INFURA_PROJECT_ID in the .env file found");
                }
            }
            else {
                apiKey = key;
            }
            switch (network) {
                case v2_sdk_1.Network.ETHEREUM:
                    url = "https://mainnet.infura.io/v3/".concat(apiKey);
                    break;
                default:
                    url = "https://".concat(network, "-mainnet.infura.io/v3/").concat(apiKey);
                    break;
            }
        case 'drpc':
            if (key == null) {
                apiKey = process.env.dRPC_API_KEY;
                if (!apiKey) {
                    throw new Error("No dRPC_API_KEY in the .env file found");
                }
            }
            else {
                apiKey = key;
            }
            url = "https://lb.drpc.org/".concat(network, "/").concat(apiKey);
            break;
        default:
            if (key == null) {
                apiKey = process.env.ALCHEMY_API_KEY;
                if (!apiKey) {
                    throw new Error("No ALCHEMY_API_KEY in the .env file found");
                }
            }
            else {
                apiKey = key;
            }
            switch (network) {
                case v2_sdk_1.Network.ARBITRUM:
                    word = 'arb';
                    break;
                case v2_sdk_1.Network.OPTIMISM:
                    word = 'opt';
                    break;
                case v2_sdk_1.Network.BASE:
                    word = 'base';
                    break;
                case v2_sdk_1.Network.POLYGON:
                    word = 'polygon';
                    break;
                default:
                    word = network;
                    break;
            }
            url = "https://".concat(word, "-mainnet.g.alchemy.com/v2/").concat(apiKey);
            break;
    }
    return url;
}
;
// Test scripts
//const network = 'ethereum' as Network;
//const key = 'AupHsm6YrU4Wkxg2M1Vgrvc6uSbSNY4R76U3hkHL9tz4';
//const provider_name = 'infura';
//const url = rpc(Network.BASE,'alchemy',null)
//console.log(url)
//const url2 = rpc(network)
//const url3 = rpc(network,provider_name)
//console.log(url)
//console.log(url2)
//console.log(url3)
//const provider = "infura" as string;
//console.log(rpc(network,provider_name))
