"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBalanceFromComposition = void 0;
//export const getBalanceFromComposition = (
//    asset: string,
//    composition: FundComposition[]
//  ): ethers.BigNumber => {
//    return composition.find((x) => x.asset.toLowerCase() === asset.toLowerCase())!
//      .balance
//  }
var getBalanceFromComposition = function (asset, composition) {
    var match = composition.find(function (x) { return x.asset.toLowerCase() === asset.toLowerCase(); });
    if (!match) {
        throw new Error("Asset ".concat(asset, " not found in pool composition"));
    }
    if (!match.balance) {
        throw new Error("Asset ".concat(asset, " found but balance is missing"));
    }
    return match.balance;
};
exports.getBalanceFromComposition = getBalanceFromComposition;
