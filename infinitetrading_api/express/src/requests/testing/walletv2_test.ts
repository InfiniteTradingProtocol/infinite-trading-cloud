import { ethers, Network } from "@dhedge/v2-sdk";
import { walletv2 } from "../../walletv2";
import { wallet } from "../../wallet";

const network = 'polygon' as Network
const apiKey = '79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688' as string;
const signer = walletv2(network,apiKey)
console.log(signer)
const signer2 = wallet(network,'infinitetrading')
const signer3 = wallet(network)
//const signer4 = wallet(network,'infinitetrading2')
console.log(signer2)
console.log(signer3)
//console.log(signer4)
