import { Network } from "../index";
export declare function getAaveV3HealthFactor(userAddress: string, network: `${Network}`, provider: string | null, apiKey: string | null): Promise<{
    healthFactor: number;
}>;
