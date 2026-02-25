"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getProvider = getProvider;
exports.walletv2 = walletv2;
var v2_sdk_1 = require("@dhedge/v2-sdk");
var rpc_1 = require("./rpc");
var child_process_1 = require("child_process");
//import { path } from 'path';
var path = require("path");
function getProvider(network, provider, key) {
    return __awaiter(this, void 0, void 0, function () {
        var providerUrl, rpc_provider;
        return __generator(this, function (_a) {
            providerUrl = (0, rpc_1.rpc)(network, provider, key);
            rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider(providerUrl);
            return [2 /*return*/, rpc_provider];
        });
    });
}
function add0xPrefix(privateKey) {
    if (!privateKey.startsWith('0x'))
        return '0x' + privateKey;
    return privateKey;
}
function runRScript(apiKey) {
    return __awaiter(this, void 0, void 0, function () {
        return __generator(this, function (_a) {
            return [2 /*return*/, new Promise(function (resolve, reject) {
                    var scriptPath = path.resolve('/home/ubuntu/infinitetrading/src/api/encryption.R');
                    (0, child_process_1.exec)("Rscript ".concat(scriptPath, " ").concat(apiKey), function (error, stdout, stderr) {
                        if (error) {
                            reject("error: ".concat(error.message));
                        }
                        if (stderr) {
                            reject("stderr: ".concat(stderr));
                        }
                        resolve(stdout.trim());
                    });
                })];
        });
    });
}
function walletv2(network_1, apiKey_1) {
    return __awaiter(this, arguments, void 0, function (network, apiKey, provider, key) {
        var privateKey, full_privateKey, rpc_provider;
        if (provider === void 0) { provider = null; }
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, runRScript(apiKey)];
                case 1:
                    privateKey = _a.sent();
                    full_privateKey = add0xPrefix(privateKey);
                    if (provider instanceof v2_sdk_1.ethers.providers.Provider)
                        rpc_provider = provider;
                    else
                        rpc_provider = new v2_sdk_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, key));
                    return [2 /*return*/, new v2_sdk_1.ethers.Wallet(full_privateKey, rpc_provider)];
            }
        });
    });
}
;
//////////////////
// Test scripts
//////////////////
//const network = 'polygon' as Network;
//const apiKey = '79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688' as string;
//const provider = 'infura'
//infura key
//const key = null
//const walletInstance = walletv2(network, apiKey,provider, key);
//console.log(`Wallet address: ${walletInstance.address}`);
//walletv2(network, apiKey, provider, key)
// .then(wallet => {
//   console.log(`Wallet address: ${wallet.address}`);
//   console.log('Wallet object:', JSON.stringify(wallet, null, 2)); // Convert wallet object to JSON string
// })
// .catch(error => {
//   console.error('Failed to create wallet object:', error);
// });
