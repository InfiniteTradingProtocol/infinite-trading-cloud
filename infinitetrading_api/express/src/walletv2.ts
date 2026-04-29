import { ethers, Network } from "@dhedge/v2-sdk";
import { rpc, getAllRpcProviders } from './rpc';
import { RetryProvider, createRetryProviderWithFailover } from './utils/RetryProvider';
import * as crypto from 'crypto';
import { dbQuery, dbExecute } from './db';

// ── UUID helper ──────────────────────────────────────────────────────────────
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isUUID(s: string): boolean { return UUID_RE.test(s); }

// ── Low-level crypto ─────────────────────────────────────────────────────────
function add0xPrefix(key: string): string {
  return key.startsWith('0x') ? key : '0x' + key;
}

/**
 * Single-layer AES-256-CBC encrypt matching R's secure_encrypt(hexmode=TRUE).
 * Input: hex string (private key bytes as hex, no 0x prefix).
 * Output: hex string — first 32 hex chars = IV (16 bytes), rest = ciphertext.
 */
function secureEncrypt(hexData: string): string {
  const encryptionKey = Buffer.from(process.env.encryption_key!, 'base64');
  const iv = crypto.randomBytes(16);
  const plaintext = Buffer.from(hexData, 'hex');
  const cipher = crypto.createCipheriv('aes-256-cbc', encryptionKey, iv);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, encrypted]).toString('hex');
}

/**
 * Single-layer AES-256-CBC decrypt matching R's secure_decrypt().
 * Input: hex string (IV prepended).
 * Output: hex string of decrypted bytes.
 */
function secureDecrypt(hexData: string): string {
  const encryptionKey = Buffer.from(process.env.encryption_key!, 'base64');
  const dataRaw = Buffer.from(hexData, 'hex');
  const iv = dataRaw.slice(0, 16);
  const ciphertext = dataRaw.slice(16);
  const decipher = crypto.createDecipheriv('aes-256-cbc', encryptionKey, iv);
  decipher.setAutoPadding(true);
  const decrypted = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return decrypted.toString('hex');
}

// ── Token-based API (new) ─────────────────────────────────────────────────────

/**
 * Generates a UUID token for the given private key:
 *  1. Derives wallet address via ethers
 *  2. Encrypts the private key (single AES-256-CBC layer)
 *  3. Stores (token, wallet_address, encrypted_pk) in api_tokens
 *  4. Returns the UUID token (this is the user's "API key")
 */
export async function generateApiToken(privateKey: string): Promise<string> {
  const normalised = add0xPrefix(privateKey);
  // Derive wallet address — throws if key is invalid
  const walletAddress = new ethers.Wallet(normalised).address;
  const hexPk = normalised.replace(/^0x/, '');
  const encryptedPk = secureEncrypt(hexPk);
  const token = crypto.randomUUID();

  await dbExecute(
    'INSERT INTO api_tokens (token, wallet_address, encrypted_pk) VALUES (?, ?, ?)',
    [token, walletAddress, encryptedPk]
  );
  return token;
}

/**
 * Returns the wallet address for a token without any decryption
 * (reads pre-stored wallet_address from api_tokens).
 */
export async function getWalletAddressFromToken(token: string): Promise<string | null> {
  const rows = await dbQuery(
    'SELECT wallet_address FROM api_tokens WHERE token = ?',
    [token]
  );
  return rows.length > 0 ? rows[0].wallet_address : null;
}

/**
 * Returns the decrypted private key for a token (used only when signing txs).
 */
async function getPrivateKeyFromToken(token: string): Promise<string> {
  const rows = await dbQuery(
    'SELECT encrypted_pk FROM api_tokens WHERE token = ?',
    [token]
  );
  if (rows.length === 0) throw new Error(`No api_token found for token: ${token}`);
  const decrypted = secureDecrypt(rows[0].encrypted_pk);
  return add0xPrefix(decrypted);
}

// ── Provider helper ───────────────────────────────────────────────────────────
export async function getProvider(network: Network, provider: string | null, key: string | null) {
  if (provider === null) {
    return createRetryProviderWithFailover(getAllRpcProviders(network));
  }
  return new RetryProvider(rpc(network, provider, key));
}

// ── walletv2 ─────────────────────────────────────────────────────────────────
/**
 * Returns an ethers.Wallet connected to the appropriate RPC provider.
 * Accepts:
 *   - UUID token  (new scheme) → looks up encrypted_pk in api_tokens
 */
export async function walletv2(
  network: Network,
  apiKey: string,
  provider: string | ethers.providers.Provider | null = null,
  key: string | null
): Promise<ethers.Wallet> {
  if (!isUUID(apiKey)) throw new Error('Invalid apiKey: expected a UUID token');

  const privateKey = await getPrivateKeyFromToken(apiKey);

  let rpc_provider: ethers.providers.Provider;
  if (provider instanceof ethers.providers.Provider) {
    rpc_provider = provider;
  } else if (provider === null) {
    rpc_provider = createRetryProviderWithFailover(getAllRpcProviders(network));
  } else {
    rpc_provider = new RetryProvider(rpc(network, provider, key));
  }
  return new ethers.Wallet(privateKey, rpc_provider);
};

//////////////////
// Test scripts
//////////////////

//const network = 'polygon' as Network;
//const apiKey = '79eb46f058cec923889383a70cd71ffb51b3c54dd421039b8855d3f46c840b5e6d1b6ce9156167cc2575c9dd8ca46826f4e40eb934cde2f3348337c4f31ca688' as string;
//const provider = 'infura'

//infura key
//const key = null


//const walletInstance = walletv2(network, apiKey,provider, key);

//console.log(`Wallet address: ${walletInstance.address}`);
//walletv2(network, apiKey, provider, key)
// .then(wallet => {
//   console.log(`Wallet address: ${wallet.address}`);
//   console.log('Wallet object:', JSON.stringify(wallet, null, 2)); // Convert wallet object to JSON string
// })
// .catch(error => {
//   console.error('Failed to create wallet object:', error);
// });
