import type { AppConfig } from '../../config.js';
import type { KrogerProductSearchResponse } from '../../contracts.js';
import {
  normalizeKrogerProducts,
  type KrogerListingContext,
} from './productNormalizer.js';

export const KROGER_PRODUCT_SCOPE = 'product.compact';

const DEFAULT_PRODUCT_QUERY = 'Soy Milk';

export type KrogerLookupOptions = {
  query?: string;
  fetchImpl?: typeof fetch;
};

export type KrogerTokenResponse = {
  ok: boolean;
  status: number;
  statusText: string;
  body?: unknown;
  tokenType?: string;
  expiresIn?: number;
  scope?: string;
};

export type KrogerProductResponse = {
  ok: boolean;
  status: number;
  statusText: string;
  body: unknown;
};

export type KrogerDiagnosticError = {
  message: string;
  code: string;
};

export type KrogerTokenResult =
  | {
      ok: true;
      accessToken: string;
      response: KrogerTokenResponse;
    }
  | {
      ok: false;
      response?: KrogerTokenResponse;
      error: KrogerDiagnosticError;
    };

export async function searchKrogerProducts(
  config: AppConfig,
  options: KrogerLookupOptions = {},
): Promise<KrogerProductSearchResponse> {
  const query = normalizeProductQuery(options.query);
  const fetchImpl = options.fetchImpl ?? fetch;
  const { clientId, clientSecret } = config.kroger;
  const generatedAt = new Date().toISOString();

  if (!clientId || !clientSecret) {
    return {
      ok: false,
      query,
      generatedAt,
      products: [],
      error: 'Missing required Kroger API environment variable(s).',
    };
  }

  const tokenURL = krogerURL(config.kroger.apiBaseURL, 'connect/oauth2/token');
  const productURL = krogerProductSearchURL(config, query);

  let tokenResult: KrogerTokenResult;

  try {
    tokenResult = await requestKrogerToken({
      fetchImpl,
      tokenURL,
      clientId,
      clientSecret,
    });
  } catch (error) {
    return {
      ok: false,
      query,
      generatedAt,
      products: [],
      error: errorMessage(error),
    };
  }

  if (!tokenResult.ok) {
    return {
      ok: false,
      query,
      generatedAt,
      productStatusCode: tokenResult.response?.status,
      products: [],
      error: tokenResult.error?.message,
    };
  }

  try {
    const productResponse = await requestKrogerProducts({
      fetchImpl,
      productURL,
      accessToken: tokenResult.accessToken,
    });

    return {
      ok: productResponse.ok,
      query,
      generatedAt,
      productStatusCode: productResponse.status,
      products: productResponse.ok ? normalizeKrogerProducts(productResponse.body, krogerListingContext(config, generatedAt)) : [],
      ...(productResponse.ok
        ? {}
        : { error: `Kroger product search returned HTTP ${productResponse.status}.` }),
    };
  } catch (error) {
    return {
      ok: false,
      query,
      generatedAt,
      products: [],
      error: errorMessage(error),
    };
  }
}

export function normalizeProductQuery(value: string | undefined): string {
  const trimmed = value?.trim();
  return trimmed ? trimmed : DEFAULT_PRODUCT_QUERY;
}

export function krogerProductSearchURL(config: AppConfig, query: string): URL {
  const productURL = krogerURL(config.kroger.apiBaseURL, 'products');
  productURL.searchParams.set('filter.term', query);
  productURL.searchParams.set('filter.limit', String(config.kroger.productSearchLimit));

  if (config.kroger.locationId) {
    productURL.searchParams.set('filter.locationId', config.kroger.locationId);
  }

  return productURL;
}

export function krogerListingContext(config: AppConfig, checkedAt: string): KrogerListingContext {
  return {
    storeId: config.kroger.shoppingStoreId,
    storeName: config.kroger.shoppingStoreName,
    locationId: config.kroger.locationId,
    checkedAt,
  };
}

export function krogerURL(baseURL: string, pathSegment: string): URL {
  const base = baseURL.endsWith('/') ? baseURL : `${baseURL}/`;
  return new URL(pathSegment, base);
}

export async function requestKrogerToken(options: {
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

export async function requestKrogerProducts(options: {
  fetchImpl: typeof fetch;
  productURL: URL;
  accessToken: string;
}): Promise<KrogerProductResponse> {
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

export function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  return String(error);
}

function tokenMetadata(value: unknown): Partial<KrogerTokenResponse> {
  if (!isRecord(value)) {
    return {};
  }

  return {
    tokenType: typeof value.token_type === 'string' ? value.token_type : undefined,
    expiresIn: typeof value.expires_in === 'number' ? value.expires_in : undefined,
    scope: typeof value.scope === 'string' ? value.scope : undefined,
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
