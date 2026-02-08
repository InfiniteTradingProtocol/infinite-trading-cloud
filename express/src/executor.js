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
var ethers_1 = require("ethers");
var axios_1 = require("axios");
//import dotenv from "dotenv";
require("dotenv").config({ path: '../.env' });
var infuraApiKey = process.env.INFURA_PROJECT_ID;
var provider = new ethers_1.ethers.providers.JsonRpcProvider("https://optimism-mainnet.infura.io/v3/".concat(infuraApiKey));
//const infuraApiKey = process.env.INFURA_PROJECT_ID;
//const provider = new ethers.providers.JsonRpcProvider('http://[2a01:240:ad00:2100:3:a883:1053:8fe1]:8545/')
console.log("Private Key:", process.env.PRIVATE_KEY); // Make sure this is not undefined
var signer = new ethers_1.ethers.Wallet(process.env.PRIVATE_KEY, provider);
// Staking contract as an example
var contractAddress = "0x23371aEEaF8718955C93aEC726b3CAFC772B9E37";
// Etherscan API key from .env
var etherscanApiKey = process.env.etherscan_optimism;
function getContractAbiAndCode() {
    return __awaiter(this, void 0, void 0, function () {
        var abiResponse, abi, contract, contractWithSigner, contractFunctions, sourceCodeResponse, sourceCode, details, error_1;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0: return [4 /*yield*/, axios_1.default.get("https://api-optimistic.etherscan.io/api?module=contract&action=getabi&address=".concat(contractAddress, "&apikey=").concat(etherscanApiKey))];
                case 1:
                    abiResponse = _a.sent();
                    abi = JSON.parse(abiResponse.data.result);
                    if (!abi) {
                        console.log("ABI not found for this contract or contract is not verified.");
                        return [2 /*return*/];
                    }
                    contract = new ethers_1.ethers.Contract(contractAddress, abi, provider);
                    contractWithSigner = new ethers_1.ethers.Contract(contractAddress, abi, signer);
                    contractFunctions = Object.keys(contract.interface.functions);
                    console.log("Functions in the Contract:");
                    console.log(contractFunctions);
                    return [4 /*yield*/, axios_1.default.get("https://api-optimistic.etherscan.io/api?module=contract&action=getsourcecode&address=".concat(contractAddress, "&apikey=").concat(etherscanApiKey))];
                case 2:
                    sourceCodeResponse = _a.sent();
                    sourceCode = sourceCodeResponse.data.result[0].SourceCode;
                    // Decode URI components if needed
                    sourceCode = decodeURIComponent(sourceCode);
                    // Check if it's a JSON-encoded string
                    try {
                        sourceCode = JSON.parse(sourceCode);
                    }
                    catch (error) {
                        // Not JSON, ignore error
                    }
                    // Output the formatted source code
                    console.log("Verified Source Code:");
                    console.log(sourceCode);
                    // Check if source code is available and verified
                    if (sourceCode === "") {
                        console.log("Source code is not verified or available.");
                    }
                    else {
                        console.log("Verified Source Code:");
                        console.log(sourceCode);
                    }
                    _a.label = 3;
                case 3:
                    _a.trys.push([3, 5, , 6]);
                    return [4 /*yield*/, contractWithSigner.rewardsLeft()];
                case 4:
                    details = _a.sent();
                    return [3 /*break*/, 6];
                case 5:
                    error_1 = _a.sent();
                    console.error("Error calling contract function:", error_1);
                    return [3 /*break*/, 6];
                case 6: return [2 /*return*/];
            }
        });
    });
}
function getContractAbiAndCode2() {
    return __awaiter(this, void 0, void 0, function () {
        var abiResponse, abi, contract, contractWithSigner_1, contractFunctions, sourceCodeResponse, sourceCode, content, error_2;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    _a.trys.push([0, 3, , 4]);
                    return [4 /*yield*/, axios_1.default.get("https://api-optimistic.etherscan.io/api?module=contract&action=getabi&address=".concat(contractAddress, "&apikey=").concat(etherscanApiKey))];
                case 1:
                    abiResponse = _a.sent();
                    abi = JSON.parse(abiResponse.data.result);
                    if (!abi) {
                        console.log("ABI not found for this contract or contract is not verified.");
                        return [2 /*return*/];
                    }
                    contract = new ethers_1.ethers.Contract(contractAddress, abi, provider);
                    contractWithSigner_1 = new ethers_1.ethers.Contract(contractAddress, abi, signer);
                    contractFunctions = Object.keys(contract.interface.functions);
                    console.log("Functions in the Contract:", contractFunctions);
                    return [4 /*yield*/, axios_1.default.get("https://api-optimistic.etherscan.io/api?module=contract&action=getsourcecode&address=".concat(contractAddress, "&apikey=").concat(etherscanApiKey))];
                case 2:
                    sourceCodeResponse = _a.sent();
                    sourceCode = sourceCodeResponse.data.result[0].SourceCode;
                    content = void 0;
                    //######################
                    //
                    // here i need to fetch the list of executable functions.
                    // this list is obtained by invoking in this contract the following function:
                    // executableFunctions()
                    // after obtaining this list, I need to 
                    // iterate over all executable functions f1,..., fn.
                    // for each function on the list, invoke the requireExeuction(f1),...,requireExecution(fn)
                    // store the list of functions that requires execution, discard the rest. r1,...,rk (list of functions that requires execution)
                    // iterate over the list of functions that requires execution
                    // simulate(execute(r1),...,execute(rk)); check if those are not malicious.
                    // execute(r1), ..., execute(rk)
                    //
                    //######################
                    contractFunctions.forEach(function (func) {
                        console.log("function name");
                        console.log(func);
                        //check if function name is the list of executable functions
                        //	
                        // Use bracket notation to invoke the function dynamically
                        contractWithSigner_1[func]()
                            .then(function (result) { console.log("Result of ".concat(func, ":"), result); })
                            .catch(function (error) { console.error("Error invoking ".concat(func, ":"), error); });
                    });
                    return [3 /*break*/, 4];
                case 3:
                    error_2 = _a.sent();
                    console.error("Error fetching contract details:", error_2);
                    return [3 /*break*/, 4];
                case 4: return [2 /*return*/];
            }
        });
    });
}
//  fetch from the registry the list of executable smart contracts;
//  fetch the smart contract code and fetch the list of executable functions
//  validate if the functions are executable or not and return the list of those who are.
//  execute the executable function in the contract.
// use the pim pim contract as the first one.
getContractAbiAndCode2().catch(function (error) { console.error("Error fetching contract details:", error); });
