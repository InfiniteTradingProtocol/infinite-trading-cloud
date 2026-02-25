export declare enum Network {
    POLYGON = "polygon",
    OPTIMISM = "optimism",
    ARBITRUM = "arbitrum",
    BASE = "base",
    ETHEREUM = "ethereum",
    LISK = "lisk",
    MODE = "mode",
    FRAXTAL = "fraxtal",
    INK = "ink",
    UNICHAIN = "unichain"
}
export declare function formatAmount(amount: string, decimals?: number): string;
export declare function formatDate(timestamp: bigint): string;
export declare function getUSDC_Address(network: `${Network}`): string;
export declare function rpc(network: `${Network}`, provider?: string | null, key?: string | null): string;
