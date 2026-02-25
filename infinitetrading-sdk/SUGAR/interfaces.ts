// interfaces.ts

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
    readableAmount: string;  // Add a new property for the formatted amount
}

export interface ReadableBribe extends Bribe {
    readableAmount: string;  // Add a new property for the formatted amount
}

