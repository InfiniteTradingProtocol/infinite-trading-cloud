import { Network } from "../index";
import { Bribe, Fee, ReadableFee, ReadableBribe } from './interfaces';
export declare function getPrice(connectors: string[], network: `${Network}`, provider: string | null, apiKey: string | null): Promise<any>;
export declare function getPriceUSDC(tokens: string[], network: `${Network}`, provider: string | null, apiKey: string | null): Promise<any>;
export declare function getReadableFees(fees: Fee[]): ReadableFee[];
export declare function getReadableBribes(bribes: Bribe[]): ReadableBribe[];
