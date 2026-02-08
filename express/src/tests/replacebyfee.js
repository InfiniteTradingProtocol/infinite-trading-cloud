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
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
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
var ethers_1 = require("ethers");
// Infura URL and Wallet Setup
//const INFURA_URL = 'https://polygon-mainnet.infura.io/v3/d18c6d8db1024751a822f8b8b208737a';
var INFURA_URL = 'https://polygon-mainnet.g.alchemy.com/v2/QR_eaiUU1cqvUYuwkyoUusEek2HCjV_J';
var PRIVATE_KEY = 'df4730a2cd828b96f7a65214e93168c00d3654a526f664d8152302467c892898'; // Your private key
var walletAddress = '0x8893Ca7295Dfb55260Ee0db7FAa03AC8dCD8F5f5';
var provider = new ethers_1.ethers.providers.JsonRpcProvider(INFURA_URL);
var wallet = new ethers_1.ethers.Wallet(PRIVATE_KEY, provider);
function replacePendingTransaction() {
    return __awaiter(this, void 0, void 0, function () {
        var nonce, tx, txResponse, receipt, error_1;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 4, , 5]);
                    return [4 /*yield*/, provider.getTransactionCount(walletAddress, 'pending')];
                case 1:
                    nonce = _a.sent();
                    console.log('Replacing pending transaction with nonce:', nonce);
                    tx = {
                        to: walletAddress, // Replace with your own address to "self-send"
                        value: ethers_1.ethers.utils.parseEther('0'), // Sending 0 MATIC to yourself
                        gasLimit: ethers_1.ethers.utils.hexlify(50000), // Small gas limit
                        maxPriorityFeePerGas: ethers_1.ethers.utils.parseUnits('100', 'gwei'), // Priority fee (increase this)
                        maxFeePerGas: ethers_1.ethers.utils.parseUnits('200', 'gwei'), // Max fee per gas (increase this)
                        nonce: nonce, // Set the same nonce as the pending transaction
                        type: 2, // EIP-1559 transaction type
                    };
                    return [4 /*yield*/, wallet.sendTransaction(tx)];
                case 2:
                    txResponse = _a.sent();
                    console.log('Replacement transaction sent:', txResponse);
                    return [4 /*yield*/, txResponse.wait()];
                case 3:
                    receipt = _a.sent();
                    console.log('Replacement transaction confirmed:', receipt);
                    return [3 /*break*/, 5];
                case 4:
                    error_1 = _a.sent();
                    console.error('Error replacing transaction:', error_1);
                    return [3 /*break*/, 5];
                case 5: return [2 /*return*/];
            }
        });
    });
}
// Execute the replacement
replacePendingTransaction();
