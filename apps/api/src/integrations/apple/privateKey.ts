import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export type APNsPrivateKeySource = 'path' | 'inline' | 'none';

export type APNsPrivateKeyLoadResult = {
  privateKey?: string;
  source: APNsPrivateKeySource;
  path?: string;
  error?: string;
  inlineKeyIgnored: boolean;
};

export type APNsPrivateKeyEnv = {
  APNS_PRIVATE_KEY?: string;
  APNS_PRIVATE_KEY_PATH?: string;
};

export function loadApnsPrivateKey(
  env: APNsPrivateKeyEnv,
  options: { cwd?: string } = {},
): APNsPrivateKeyLoadResult {
  const privateKeyPath = readOptionalString(env.APNS_PRIVATE_KEY_PATH);
  const inlineKey = readOptionalString(env.APNS_PRIVATE_KEY);

  if (privateKeyPath) {
    const resolvedPath = resolvePrivateKeyPath(privateKeyPath, options.cwd);

    try {
      return {
        privateKey: normalizeApnsPrivateKey(fs.readFileSync(resolvedPath, 'utf8'), 'APNS_PRIVATE_KEY_PATH'),
        source: 'path',
        path: resolvedPath,
        inlineKeyIgnored: Boolean(inlineKey),
      };
    } catch (error) {
      return {
        source: 'path',
        path: resolvedPath,
        error: error instanceof Error ? error.message : String(error),
        inlineKeyIgnored: Boolean(inlineKey),
      };
    }
  }

  const privateKey = getApnsPrivateKey(inlineKey);

  return privateKey
    ? { privateKey, source: 'inline', inlineKeyIgnored: false }
    : { source: 'none', inlineKeyIgnored: false };
}

export const getApnsPrivateKey = (inlineKey: string | undefined): string | undefined => {
  if (!readOptionalString(inlineKey)) {
    return undefined;
  }

  return normalizeApnsPrivateKey(inlineKey, 'APNS_PRIVATE_KEY');
};

function normalizeApnsPrivateKey(rawKey: string | undefined, label: string): string {
  const trimmedKey = rawKey?.trim();

  if (!trimmedKey) {
    throw new Error(`${label} is empty.`);
  }

  const unquotedKey =
    (trimmedKey.startsWith('"') && trimmedKey.endsWith('"')) ||
    (trimmedKey.startsWith("'") && trimmedKey.endsWith("'"))
      ? trimmedKey.slice(1, -1)
      : trimmedKey;
  const privateKey = unquotedKey.replace(/\\n/g, '\n').trim();

  if (
    !privateKey.includes('-----BEGIN PRIVATE KEY-----') ||
    !privateKey.includes('-----END PRIVATE KEY-----')
  ) {
    throw new Error(`${label} is not a valid .p8 private key value.`);
  }

  validateParseablePrivateKey(privateKey, label);

  return privateKey;
}

function validateParseablePrivateKey(privateKey: string, label: string): void {
  try {
    crypto.createPrivateKey(privateKey);
  } catch {
    throw new Error(`${label} is not a parseable .p8 private key value.`);
  }
}

function resolvePrivateKeyPath(privateKeyPath: string, cwd = process.cwd()): string {
  return path.isAbsolute(privateKeyPath) ? privateKeyPath : path.resolve(cwd, privateKeyPath);
}

function readOptionalString(value: string | undefined): string | undefined {
  const trimmedValue = value?.trim();

  return trimmedValue ? trimmedValue : undefined;
}
