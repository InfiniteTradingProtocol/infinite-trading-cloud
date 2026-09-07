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
    // Be explicit that this compares contract addresses. The old wording
    // ("Asset USDC not found") was misleading when a symbol was passed: the
    // asset was in the vault, it just never matched an address comparison.
    throw new Error(
      `Asset ${asset} not found in pool composition (composition is keyed by contract address; ` +
      `pass a 0x address or a symbol the API can resolve)`
    );
  }

  if (!match.balance) {
    throw new Error(`Asset ${asset} found but balance is missing`);
  }

  return match.balance;
};

