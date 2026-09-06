/**
 * dhedgeTrader.ts — Node port of R's helpers/graphQL.R getPoolTrader() and
 * helpers/apiHelpers.R isValidTrader().
 *
 * PARITY NOTES:
 *  - Same dHEDGE GraphQL endpoint (https://api-v2.dhedge.org/graphql), same
 *    query shape (`allFundsByAddresses(addresses: "<pool>") { traderAddress }`),
 *    same "protocol must be dhedge" guard (R's getPoolTrader only has a body
 *    for `if (protocol == "dhedge")`; any other protocol falls through to an
 *    implicit NULL return in R, replicated here as returning null).
 *  - isValidTrader() compares lower-cased addresses, exactly like R's
 *    `tolower(getPoolTrader(...)) == tolower(trader)`.
 *  - On GraphQL errors or no data, R logs and returns NULL — replicated here
 *    (returns null, caller treats null as "not a valid trader").
 */

const DHEDGE_GRAPHQL_URL = 'https://api-v2.dhedge.org/graphql';

interface GraphQLResponse {
  errors?: { message: string }[];
  data?: {
    allFundsByAddresses?: { traderAddress: string }[];
  };
}

/** Port of R's getPoolTrader(protocol, pool). Only "dhedge" is supported (matches R). */
export async function getPoolTrader(protocol: string, pool: string): Promise<string | null> {
  if (protocol !== 'dhedge') return null;

  const query = `query allFundsByAddresses { allFundsByAddresses(addresses: "${pool}") { traderAddress } }`;

  try {
    const resp = await fetch(DHEDGE_GRAPHQL_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, variables: {}, operationName: 'allFundsByAddresses' }),
    });
    const result = (await resp.json()) as GraphQLResponse;

    if (result.errors && result.errors.length > 0) {
      console.log('Error:', result.errors[0].message);
      return null;
    }
    if (result.data?.allFundsByAddresses && result.data.allFundsByAddresses.length > 0) {
      return result.data.allFundsByAddresses[0].traderAddress;
    }
    console.log('No data found or invalid address provided.');
    return null;
  } catch (e: any) {
    console.log('Error fetching pool trader:', e.message);
    return null;
  }
}

/** Port of R's isValidTrader(protocol, pool, trader). */
export async function isValidTrader(protocol: string, pool: string, trader: string): Promise<boolean> {
  const poolTrader = await getPoolTrader(protocol, pool);
  if (poolTrader === null) return false;
  return poolTrader.toLowerCase() === trader.toLowerCase();
}
