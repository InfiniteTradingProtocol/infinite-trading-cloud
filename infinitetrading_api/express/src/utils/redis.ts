// src/utils/redis.ts (CJS-friendly with dynamic import)
import type { RedisClientType } from "redis"; // type-only; no runtime ESM import

let _client: RedisClientType | null = null;

async function getClient(): Promise<RedisClientType> {
  if (_client && _client.isOpen) return _client;
  // dynamic ESM import works fine in CJS builds
  const { createClient } = await import("redis");
  const r = createClient({ url: "redis://localhost:6379" });
  if (!r.isOpen) await r.connect();
  _client = r as RedisClientType;
  return _client;
}

export async function getPriceFromRedis(pair: string, exchange: string): Promise<string | null> {
  const r = await getClient();
  const key = `${exchange}_${pair}`;
  const v = await r.get(key);
  if (!v) throw new Error(`Missing USD price in Redis for ${pair}`);
  return v;
}


// Example usage
//
//getPriceFromRedis("ETH-USD","coinbase").then(console.log).catch(console.error);

//
//
// how to compile this file:
//  sudo npx tsc src/utils/redis.ts   --outDir build   --rootDir .   --module commonjs   --target ES2015   --moduleResolution Node   --esModuleInterop   --resolveJsonModule   --strict   --skipLibCheck   --types node
