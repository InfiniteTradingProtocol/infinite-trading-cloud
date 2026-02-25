export interface Bribe {
    index: number;
    token: string;
    amount: string;
}
export interface Fee {
    index: number;
    token: string;
    amount: string;
}
export interface EpochData {
    epochIndex: number;
    timestamp: bigint;
    lp: string;
    votes: number;
    emissions: number;
    bribes: Bribe[];
    fees: Fee[];
}
export interface ReadableFee extends Fee {
    readableAmount: string;
}
export interface ReadableBribe extends Bribe {
    readableAmount: string;
}
