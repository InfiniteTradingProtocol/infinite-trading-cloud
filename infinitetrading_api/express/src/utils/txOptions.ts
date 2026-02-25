import { Network } from "@dhedge/v2-sdk";
import axios from "axios";
import { ethers } from 'ethers';
import BigNumber from "bignumber.js";

export const getTxOptions = async (network: Network,provider: string | null,key: string | null): Promise<any> => {
  if (network === Network.POLYGON) {
    const result = await axios("https://gasstation.polygon.technology/v2");
    return {
      gasLimit: "600000",
      maxPriorityFeePerGas: new BigNumber(result.data.fast.maxPriorityFee)
        .shiftedBy(9)
        .toFixed(0),
      maxFeePerGas: new BigNumber(result.data.fast.maxFee)
        .shiftedBy(9)
        .toFixed(0),
    };
  } else {
    return { gasLimit: "3000000" };
  } 
};

//export const getTxOptions2 = async (network: Network, provider: string | null, key: string | null): Promise<any> => {
//  if (network === Network.POLYGON) {
//    const result = await axios("https://gasstation.polygon.technology/v2");
//    return {
//      gasLimit: "10000000",
//      maxPriorityFeePerGas: ethers.BigNumber.from(Math.round(result.data.fast.maxPriorityFee * 1e9)).toString(),
//      maxFeePerGas: ethers.BigNumber.from(Math.round(result.data.fast.maxFee * 1e9)).toString(),
//    };
//  } else {
//    return { gasLimit: "3500000" };
//  }
//};

//(async () => {
//  try {
//    const txOptions = await getTxOptions(Network.POLYGON, 'infura', null);
//   console.log('getTxOptions result:', txOptions);
//
//    const txOptions2 = await getTxOptions2(Network.POLYGON, 'infura', null);
//    console.log('getTxOptions2 result:', txOptions2);
//  } catch (error) {
//    console.error('Error fetching transaction options:', error);
//  }
//})();
