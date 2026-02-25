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
exports.getPoolAaveData = getPoolAaveData;
exports.getAaveV3HealthFactor = getAaveV3HealthFactor;
exports.getSupplied = getSupplied;
exports.getBorrowed = getBorrowed;
exports.getAllSupplied = getAllSupplied;
exports.getAllBorrowed = getAllBorrowed;
// utils/aave.ts
var rpc_1 = require("../rpc");
var ethers_1 = require("ethers");
var IAddressesProviderAbi = [
    "function getPool() external view returns (address)",
];
var IPoolAbi = [
    // indices: 0..5; healthFactor is index 5
    "function getUserAccountData(address user) external view returns (uint256,uint256,uint256,uint256,uint256,uint256)",
];
var IPoolExtAbi = [
    // For getAll*, we need the reserves list
    "function getReservesList() view returns (address[])",
    // We use getReserveData(asset) to discover aToken / debt token addresses
    // ABI matches Aave v3 ReserveData shape enough to access address fields by index.
    "function getReserveData(address asset) view returns (tuple(tuple(uint256 data) configuration,uint128 liquidityIndex,uint128 currentLiquidityRate,uint128 variableBorrowIndex,uint128 currentVariableBorrowRate,uint128 currentStableBorrowRate,uint40 lastUpdateTimestamp,uint16 id,address aTokenAddress,address stableDebtTokenAddress,address variableDebtTokenAddress,address interestRateStrategyAddress,uint128 accruedToTreasury,uint128 unbackedMintCap,uint128 debtCeiling,uint16 debtCeilingDecimals,uint8 eModeCategoryId,uint16 liquidationProtocolFee,uint128 unbackedMinted,uint128 isolationModeTotalDebt,uint128 virtualAccruedToTreasury))",
];
var IERC20MinimalAbi = [
    "function balanceOf(address) view returns (uint256)",
    "function decimals() view returns (uint8)",
];
function fmt(x, decimals) {
    return ethers_1.ethers.utils.formatUnits(x, decimals);
}
function pick(data, namedKey, index) {
    if (data && typeof data === "object" && namedKey in data)
        return data[namedKey];
    if (Array.isArray(data))
        return data[index];
    return undefined;
}
function getPoolAaveData(userAddress, network, provider, providerApiKey, contractAddress // Pool OR PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, data, totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor, formatted;
        var _b, _c, _d, _e, _f, _g;
        return __generator(this, function (_h) {
            switch (_h.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _h.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _h.label = 2;
                case 2:
                    _h.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _h.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _h.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolAbi, rpcProvider);
                    return [4 /*yield*/, pool.getUserAccountData(userAddress)];
                case 6:
                    data = _h.sent();
                    totalCollateralBase = (_b = pick(data, "totalCollateralBase", 0)) !== null && _b !== void 0 ? _b : (function () { throw new Error("totalCollateralBase missing from getUserAccountData"); })();
                    totalDebtBase = (_c = pick(data, "totalDebtBase", 1)) !== null && _c !== void 0 ? _c : (function () { throw new Error("totalDebtBase missing from getUserAccountData"); })();
                    availableBorrowsBase = (_d = pick(data, "availableBorrowsBase", 2)) !== null && _d !== void 0 ? _d : (function () { throw new Error("availableBorrowsBase missing from getUserAccountData"); })();
                    currentLiquidationThreshold = (_e = pick(data, "currentLiquidationThreshold", 3)) !== null && _e !== void 0 ? _e : (function () { throw new Error("currentLiquidationThreshold missing from getUserAccountData"); })();
                    ltv = (_f = pick(data, "ltv", 4)) !== null && _f !== void 0 ? _f : (function () { throw new Error("ltv missing from getUserAccountData"); })();
                    healthFactor = (_g = pick(data, "healthFactor", 5)) !== null && _g !== void 0 ? _g : (function () { throw new Error("healthFactor missing from getUserAccountData"); })();
                    formatted = {
                        totalCollateralBase: fmt(totalCollateralBase, 8), // base currency decimals (1e8)
                        totalDebtBase: fmt(totalDebtBase, 8),
                        availableBorrowsBase: fmt(availableBorrowsBase, 8),
                        currentLiquidationThreshold: fmt(currentLiquidationThreshold, 4), // e.g. "0.78"
                        ltv: fmt(ltv, 4), // e.g. "0.73"
                        healthFactor: fmt(healthFactor, 18), // ray → decimal
                    };
                    return [2 /*return*/, { formatted: formatted }];
            }
        });
    });
}
function getAaveV3HealthFactor(userAddress, network, provider, providerApiKey, contractAddress // Pool or PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, data, hfRay, keys, healthFactor;
        var _b;
        return __generator(this, function (_c) {
            switch (_c.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _c.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _c.label = 2;
                case 2:
                    _c.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _c.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _c.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolAbi, rpcProvider);
                    return [4 /*yield*/, pool.getUserAccountData(userAddress)];
                case 6:
                    data = _c.sent();
                    hfRay = (_b = (data && typeof data === "object" && "healthFactor" in data ? data.healthFactor : undefined)) !== null && _b !== void 0 ? _b : (Array.isArray(data) ? data[5] : data === null || data === void 0 ? void 0 : data[5]);
                    if (hfRay == null) {
                        keys = data && typeof data === "object" ? Object.keys(data) : [];
                        throw new Error("healthFactor missing from getUserAccountData result (keys: ".concat(keys.join(","), ")"));
                    }
                    healthFactor = Number(ethers_1.ethers.utils.formatUnits(hfRay, 18));
                    return [2 /*return*/, healthFactor];
            }
        });
    });
}
// ------------------------------ getSupplied ------------------------------
function getSupplied(userAddress, asset, // underlying token (e.g., USDC). We'll report balance keyed by this address.
network, provider, providerApiKey, contractAddress // Pool OR PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, reserveData, aTokenAddress, aToken, underlying, _b, raw, decimals;
        var _c;
        var _d;
        return __generator(this, function (_e) {
            switch (_e.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _e.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _e.label = 2;
                case 2:
                    _e.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _e.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _e.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
                    return [4 /*yield*/, pool.getReserveData(asset)];
                case 6:
                    reserveData = _e.sent();
                    aTokenAddress = (_d = pick(reserveData, "aTokenAddress", 8)) !== null && _d !== void 0 ? _d : (function () {
                        throw new Error("aTokenAddress missing from getReserveData");
                    })();
                    aToken = new ethers_1.ethers.Contract(aTokenAddress, IERC20MinimalAbi, rpcProvider);
                    underlying = new ethers_1.ethers.Contract(asset, IERC20MinimalAbi, rpcProvider);
                    return [4 /*yield*/, Promise.all([
                            aToken.balanceOf(userAddress),
                            underlying.decimals(),
                        ])];
                case 7:
                    _b = _e.sent(), raw = _b[0], decimals = _b[1];
                    return [2 /*return*/, (_c = {}, _c[asset] = ethers_1.ethers.utils.formatUnits(raw, decimals), _c)];
            }
        });
    });
}
// ------------------------------ getBorrowed ------------------------------
function getBorrowed(userAddress, asset, // underlying token address; result keyed by this address
network, provider, providerApiKey, contractAddress // Pool OR PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, reserveData, stableDebtTokenAddress, variableDebtTokenAddress, stableDebt, variableDebt, underlying, _b, sBal, vBal, decimals, total;
        var _c;
        var _d, _e;
        return __generator(this, function (_f) {
            switch (_f.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _f.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _f.label = 2;
                case 2:
                    _f.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _f.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _f.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
                    return [4 /*yield*/, pool.getReserveData(asset)];
                case 6:
                    reserveData = _f.sent();
                    stableDebtTokenAddress = (_d = pick(reserveData, "stableDebtTokenAddress", 9)) !== null && _d !== void 0 ? _d : (function () {
                        throw new Error("stableDebtTokenAddress missing from getReserveData");
                    })();
                    variableDebtTokenAddress = (_e = pick(reserveData, "variableDebtTokenAddress", 10)) !== null && _e !== void 0 ? _e : (function () {
                        throw new Error("variableDebtTokenAddress missing from getReserveData");
                    })();
                    stableDebt = new ethers_1.ethers.Contract(stableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
                    variableDebt = new ethers_1.ethers.Contract(variableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
                    underlying = new ethers_1.ethers.Contract(asset, IERC20MinimalAbi, rpcProvider);
                    return [4 /*yield*/, Promise.all([
                            stableDebt.balanceOf(userAddress),
                            variableDebt.balanceOf(userAddress),
                            underlying.decimals(),
                        ])];
                case 7:
                    _b = _f.sent(), sBal = _b[0], vBal = _b[1], decimals = _b[2];
                    total = ethers_1.BigNumber.from(sBal).add(vBal);
                    return [2 /*return*/, (_c = {}, _c[asset] = ethers_1.ethers.utils.formatUnits(total, decimals), _c)];
            }
        });
    });
}
// ------------------------------ getAllSupplied (if possible) ------------------------------
function getAllSupplied(userAddress, _asset, // unused; kept to match requested signature
network, provider, providerApiKey, contractAddress // Pool OR PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, reserves, out, _i, reserves_1, reserve, reserveData, aTokenAddress, aToken, underlying, _b, raw, decimals;
        var _c;
        return __generator(this, function (_d) {
            switch (_d.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _d.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _d.label = 2;
                case 2:
                    _d.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _d.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _d.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
                    return [4 /*yield*/, pool.getReservesList()];
                case 6:
                    reserves = _d.sent();
                    out = {};
                    _i = 0, reserves_1 = reserves;
                    _d.label = 7;
                case 7:
                    if (!(_i < reserves_1.length)) return [3 /*break*/, 11];
                    reserve = reserves_1[_i];
                    return [4 /*yield*/, pool.getReserveData(reserve)];
                case 8:
                    reserveData = _d.sent();
                    aTokenAddress = (_c = pick(reserveData, "aTokenAddress", 8)) !== null && _c !== void 0 ? _c : (function () {
                        throw new Error("aTokenAddress missing from getReserveData");
                    })();
                    aToken = new ethers_1.ethers.Contract(aTokenAddress, IERC20MinimalAbi, rpcProvider);
                    underlying = new ethers_1.ethers.Contract(reserve, IERC20MinimalAbi, rpcProvider);
                    return [4 /*yield*/, Promise.all([
                            aToken.balanceOf(userAddress),
                            underlying.decimals(),
                        ])];
                case 9:
                    _b = _d.sent(), raw = _b[0], decimals = _b[1];
                    if (!raw.isZero()) {
                        out[reserve] = ethers_1.ethers.utils.formatUnits(raw, decimals);
                    }
                    _d.label = 10;
                case 10:
                    _i++;
                    return [3 /*break*/, 7];
                case 11: return [2 /*return*/, out];
            }
        });
    });
}
// ------------------------------ getAllBorrowed (if possible) ------------------------------
function getAllBorrowed(userAddress, _asset, // unused; kept to match requested signature
network, provider, providerApiKey, contractAddress // Pool OR PoolAddressesProvider
) {
    return __awaiter(this, void 0, void 0, function () {
        var rpcProvider, code, poolAddress, addressesProvider, resolved, _a, pool, reserves, out, _i, reserves_2, reserve, reserveData, stableDebtTokenAddress, variableDebtTokenAddress, stableDebt, variableDebt, underlying, _b, sBal, vBal, decimals, total;
        var _c, _d;
        return __generator(this, function (_e) {
            switch (_e.label) {
                case 0:
                    rpcProvider = new ethers_1.ethers.providers.JsonRpcProvider((0, rpc_1.rpc)(network, provider, providerApiKey));
                    return [4 /*yield*/, rpcProvider.getCode(contractAddress)];
                case 1:
                    code = _e.sent();
                    if (code === "0x") {
                        throw new Error("No contract code at ".concat(contractAddress));
                    }
                    poolAddress = contractAddress;
                    _e.label = 2;
                case 2:
                    _e.trys.push([2, 4, , 5]);
                    addressesProvider = new ethers_1.ethers.Contract(contractAddress, IAddressesProviderAbi, rpcProvider);
                    return [4 /*yield*/, addressesProvider.getPool()];
                case 3:
                    resolved = _e.sent();
                    if (resolved && ethers_1.ethers.utils.isAddress(resolved)) {
                        poolAddress = resolved;
                    }
                    return [3 /*break*/, 5];
                case 4:
                    _a = _e.sent();
                    return [3 /*break*/, 5];
                case 5:
                    pool = new ethers_1.ethers.Contract(poolAddress, IPoolExtAbi, rpcProvider);
                    return [4 /*yield*/, pool.getReservesList()];
                case 6:
                    reserves = _e.sent();
                    out = {};
                    _i = 0, reserves_2 = reserves;
                    _e.label = 7;
                case 7:
                    if (!(_i < reserves_2.length)) return [3 /*break*/, 11];
                    reserve = reserves_2[_i];
                    return [4 /*yield*/, pool.getReserveData(reserve)];
                case 8:
                    reserveData = _e.sent();
                    stableDebtTokenAddress = (_c = pick(reserveData, "stableDebtTokenAddress", 9)) !== null && _c !== void 0 ? _c : (function () {
                        throw new Error("stableDebtTokenAddress missing from getReserveData");
                    })();
                    variableDebtTokenAddress = (_d = pick(reserveData, "variableDebtTokenAddress", 10)) !== null && _d !== void 0 ? _d : (function () {
                        throw new Error("variableDebtTokenAddress missing from getReserveData");
                    })();
                    stableDebt = new ethers_1.ethers.Contract(stableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
                    variableDebt = new ethers_1.ethers.Contract(variableDebtTokenAddress, IERC20MinimalAbi, rpcProvider);
                    underlying = new ethers_1.ethers.Contract(reserve, IERC20MinimalAbi, rpcProvider);
                    return [4 /*yield*/, Promise.all([
                            stableDebt.balanceOf(userAddress),
                            variableDebt.balanceOf(userAddress),
                            underlying.decimals(),
                        ])];
                case 9:
                    _b = _e.sent(), sBal = _b[0], vBal = _b[1], decimals = _b[2];
                    total = ethers_1.BigNumber.from(sBal).add(vBal);
                    if (!total.isZero()) {
                        out[reserve] = ethers_1.ethers.utils.formatUnits(total, decimals);
                    }
                    _e.label = 10;
                case 10:
                    _i++;
                    return [3 /*break*/, 7];
                case 11: return [2 /*return*/, out];
            }
        });
    });
}
