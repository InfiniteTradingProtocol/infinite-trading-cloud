import { GraphQLClient, gql } from "graphql-request";

const AAVE_SUBGRAPH_URL = "https://api.thegraph.com/subgraphs/name/aave/protocol-v2";

interface ReserveData {
  symbol: string;
  liquidityRate: string; // Lending APR (scaled by 1e27)
  variableBorrowRate: string; // Variable borrowing APR (scaled by 1e27)
  stableBorrowRate: string; // Stable borrowing APR (scaled by 1e27)
}

async function fetchAssetAPR(assetSymbol: string): Promise<void> {
  const client = new GraphQLClient(AAVE_SUBGRAPH_URL);

  const query = gql`
    query getAssetAPR($symbol: String!) {
      reserves(where: { symbol: $symbol }) {
        symbol
        liquidityRate
        variableBorrowRate
        stableBorrowRate
      }
    }
  `;

  try {
    const variables = { symbol: assetSymbol };
    const data = await client.request<{ reserves: ReserveData[] }>(query, variables);

    if (data.reserves.length === 0) {
      console.log(`No data found for asset symbol: ${assetSymbol}`);
      return;
    }

    const reserve = data.reserves[0];
    const lendingAPR = parseFloat(reserve.liquidityRate) / 1e27 * 100; // Convert to percentage
    const variableBorrowAPR = parseFloat(reserve.variableBorrowRate) / 1e27 * 100; // Convert to percentage
    const stableBorrowAPR = parseFloat(reserve.stableBorrowRate) / 1e27 * 100; // Convert to percentage

    console.log(`Asset: ${reserve.symbol}`);
    console.log(`Lending APR: ${lendingAPR.toFixed(2)}%`);
    console.log(`Variable Borrowing APR: ${variableBorrowAPR.toFixed(2)}%`);
    console.log(`Stable Borrowing APR: ${stableBorrowAPR.toFixed(2)}%`);
  } catch (error) {
    console.error("Error fetching APRs:", error);
  }
}

// Replace "DAI" with the symbol of the asset you want to query
fetchAssetAPR("DAI");

