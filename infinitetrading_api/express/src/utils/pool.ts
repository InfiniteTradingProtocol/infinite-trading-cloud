import { ethers, FundComposition } from "@dhedge/v2-sdk"

//export const getBalanceFromComposition = (
//    asset: string,
//    composition: FundComposition[]
//  ): ethers.BigNumber => {
//    return composition.find((x) => x.asset.toLowerCase() === asset.toLowerCase())!
//      .balance
//  }
export const getBalanceFromComposition = (
  asset: string,
  composition: FundComposition[]
): ethers.BigNumber => {
  const match = composition.find((x) => x.asset.toLowerCase() === asset.toLowerCase());

  if (!match) {
    throw new Error(`Asset ${asset} not found in pool composition`);
  }

  if (!match.balance) {
    throw new Error(`Asset ${asset} found but balance is missing`);
  }

  return match.balance;
};

