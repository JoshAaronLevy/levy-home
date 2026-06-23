import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { AppConfig } from './config.js';

const KROGER_PRODUCT_SCOPE = 'product.compact';
const DEFAULT_PRODUCT_QUERY = 'Soy Milk';

type KrogerDiagnosticStage = 'configuration' | 'token' | 'product_search';

type KrogerDiagnosticRecord = {
  ok: boolean;
  query: string;
  generatedAt: string;
  stage: KrogerDiagnosticStage;
  outputFilePath: string;
  tokenRequest?: {
    method: 'POST';
    url: string;
    scope: string;
  };
  tokenResponse?: {
    ok: boolean;
    status: number;
    statusText: string;
    body?: unknown;
    tokenType?: string;
    expiresIn?: number;
    scope?: string;
  };
  productRequest?: {
    method: 'GET';
    url: string;
  };
  productResponse?: {
    ok: boolean;
    status: number;
    statusText: string;
    body: unknown;
  };
  error?: {
    message: string;
    code: string;
  };
};

export type KrogerProductDiagnosticSummary = {
  ok: boolean;
  query: string;
  generatedAt: string;
  stage: KrogerDiagnosticStage;
  outputFilePath: string;
  tokenStatusCode?: number;
  productStatusCode?: number;
  error?: string;
};

export type KrogerProductDiagnosticRunner = (query?: string) => Promise<KrogerProductDiagnosticSummary>;

type KrogerLookupOptions = {
  query?: string;
  fetchImpl?: typeof fetch;
};

type KrogerTokenResult =
  | {
      ok: true;
      accessToken: string;
      response: KrogerDiagnosticRecord['tokenResponse'];
    }
  | {
      ok: false;
      response?: KrogerDiagnosticRecord['tokenResponse'];
      error: KrogerDiagnosticRecord['error'];
    };

export async function lookupAndWriteKrogerProductResponse(
  config: AppConfig,
  options: KrogerLookupOptions = {},
): Promise<KrogerProductDiagnosticSummary> {
  const query = normalizeProductQuery(options.query);
  const outputFilePath = config.kroger.productResponseFilePath;
  const fetchImpl = options.fetchImpl ?? fetch;
  const { clientId, clientSecret } = config.kroger;

  const missingEnvNames = [
    clientId ? undefined : 'KROGER_CLIENT_ID',
    clientSecret ? undefined : 'KROGER_CLIENT_SECRET',
  ].filter((name): name is string => Boolean(name));

  if (!clientId || !clientSecret) {
    const record = createDiagnosticRecord({
      ok: false,
      query,
      outputFilePath,
      stage: 'configuration',
      error: {
        code: 'missing_kroger_credentials',
        message: `Missing required Kroger API environment variable(s): ${missingEnvNames.join(', ')}.`,
      },
    });

    await writeDiagnosticRecord(record);
    return summarizeDiagnosticRecord(record);
  }

  const tokenURL = krogerURL(config.kroger.apiBaseURL, 'connect/oauth2/token');
  const productURL = krogerURL(config.kroger.apiBaseURL, 'products');
  productURL.searchParams.set('filter.term', query);
  productURL.searchParams.set('filter.limit', String(config.kroger.productSearchLimit));

  const tokenRequest = {
    method: 'POST' as const,
    url: tokenURL.toString(),
    scope: KROGER_PRODUCT_SCOPE,
  };

  let tokenResult: KrogerTokenResult;

  try {
    tokenResult = await requestKrogerToken({
      fetchImpl,
      tokenURL,
      clientId,
      clientSecret,
    });
  } catch (error) {
    const record = createDiagnosticRecord({
      ok: false,
      query,
      outputFilePath,
      stage: 'token',
      tokenRequest,
      error: {
        code: 'kroger_token_request_failed',
        message: errorMessage(error),
      },
    });

    await writeDiagnosticRecord(record);
    return summarizeDiagnosticRecord(record);
  }

  if (!tokenResult.ok) {
    const record = createDiagnosticRecord({
      ok: false,
      query,
      outputFilePath,
      stage: 'token',
      tokenRequest,
      tokenResponse: tokenResult.response,
      error: tokenResult.error,
    });

    await writeDiagnosticRecord(record);
    return summarizeDiagnosticRecord(record);
  }

  try {
    const productResponse = await requestKrogerProducts({
      fetchImpl,
      productURL,
      accessToken: tokenResult.accessToken,
    });
    const record = createDiagnosticRecord({
      ok: productResponse.ok,
      query,
      outputFilePath,
      stage: 'product_search',
      tokenRequest,
      tokenResponse: tokenResult.response,
      productRequest: {
        method: 'GET',
        url: productURL.toString(),
      },
      productResponse,
      ...(productResponse.ok
        ? {}
        : {
            error: {
              code: 'kroger_product_search_failed',
              message: `Kroger product search returned HTTP ${productResponse.status}.`,
            },
          }),
    });

    await writeDiagnosticRecord(record);
    return summarizeDiagnosticRecord(record);
  } catch (error) {
    const record = createDiagnosticRecord({
      ok: false,
      query,
      outputFilePath,
      stage: 'product_search',
      tokenRequest,
      tokenResponse: tokenResult.response,
      productRequest: {
        method: 'GET',
        url: productURL.toString(),
      },
      error: {
        code: 'kroger_product_search_request_failed',
        message: errorMessage(error),
      },
    });

    await writeDiagnosticRecord(record);
    return summarizeDiagnosticRecord(record);
  }
}

function normalizeProductQuery(value: string | undefined): string {
  const trimmed = value?.trim();
  return trimmed ? trimmed : DEFAULT_PRODUCT_QUERY;
}

function krogerURL(baseURL: string, pathSegment: string): URL {
  const base = baseURL.endsWith('/') ? baseURL : `${baseURL}/`;
  return new URL(pathSegment, base);
}

async function requestKrogerToken(options: {
  fetchImpl: typeof fetch;
  tokenURL: URL;
  clientId: string;
  clientSecret: string;
}): Promise<KrogerTokenResult> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    scope: KROGER_PRODUCT_SCOPE,
  });
  const basicAuth = Buffer.from(`${options.clientId}:${options.clientSecret}`).toString('base64');
  const response = await options.fetchImpl(options.tokenURL, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      Authorization: `Basic ${basicAuth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const responseBody = await readResponseBody(response);
  const tokenResponse = {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    ...(response.ok ? tokenMetadata(responseBody) : { body: redactTokenPayload(responseBody) }),
  };

  if (!response.ok) {
    return {
      ok: false,
      response: tokenResponse,
      error: {
        code: 'kroger_token_rejected',
        message: `Kroger token request returned HTTP ${response.status}.`,
      },
    };
  }

  if (!isRecord(responseBody) || typeof responseBody.access_token !== 'string' || !responseBody.access_token) {
    return {
      ok: false,
      response: {
        ...tokenResponse,
        body: redactTokenPayload(responseBody),
      },
      error: {
        code: 'kroger_token_missing_access_token',
        message: 'Kroger token response did not include an access token.',
      },
    };
  }

  return {
    ok: true,
    accessToken: responseBody.access_token,
    response: tokenResponse,
  };
}

async function requestKrogerProducts(options: {
  fetchImpl: typeof fetch;
  productURL: URL;
  accessToken: string;
}): Promise<NonNullable<KrogerDiagnosticRecord['productResponse']>> {
  const response = await options.fetchImpl(options.productURL, {
    method: 'GET',
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${options.accessToken}`,
    },
  });
  const body = await readResponseBody(response);

  return {
    ok: response.ok,
    status: response.status,
    statusText: response.statusText,
    body,
  };
}

async function readResponseBody(response: Response): Promise<unknown> {
  const text = await response.text();

  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function tokenMetadata(value: unknown): Partial<NonNullable<KrogerDiagnosticRecord['tokenResponse']>> {
  if (!isRecord(value)) {
    return {};
  }

  return {
    tokenType: typeof value.token_type === 'string' ? value.token_type : undefined,
    expiresIn: typeof value.expires_in === 'number' ? value.expires_in : undefined,
    scope: typeof value.scope === 'string' ? value.scope : undefined,
  };
}

function createDiagnosticRecord(
  record: Omit<KrogerDiagnosticRecord, 'generatedAt'> & { generatedAt?: string },
): KrogerDiagnosticRecord {
  return {
    generatedAt: record.generatedAt ?? new Date().toISOString(),
    ...record,
  };
}

async function writeDiagnosticRecord(record: KrogerDiagnosticRecord): Promise<void> {
  await mkdir(path.dirname(record.outputFilePath), { recursive: true });
  await writeFile(record.outputFilePath, `${JSON.stringify(record, null, 2)}\n`, 'utf8');
}

function summarizeDiagnosticRecord(record: KrogerDiagnosticRecord): KrogerProductDiagnosticSummary {
  return {
    ok: record.ok,
    query: record.query,
    generatedAt: record.generatedAt,
    stage: record.stage,
    outputFilePath: record.outputFilePath,
    tokenStatusCode: record.tokenResponse?.status,
    productStatusCode: record.productResponse?.status,
    error: record.error?.message,
  };
}

function redactTokenPayload(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(redactTokenPayload);
  }

  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, entryValue]) => [
      key,
      shouldRedactKey(key) ? '[redacted]' : redactTokenPayload(entryValue),
    ]),
  );
}

function shouldRedactKey(key: string): boolean {
  return ['access_token', 'refresh_token', 'id_token', 'client_secret', 'token'].includes(key.toLowerCase());
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}
