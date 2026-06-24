import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { AppConfig } from './config.js';
import type {
  KrogerProductSearchResponse,
  KrogerProductSearchResult,
  ShoppingItemStoreListing,
} from './contracts.js';

const KROGER_PRODUCT_SCOPE = 'product.compact';
const DEFAULT_PRODUCT_QUERY = 'Soy Milk';

type KrogerDiagnosticStage = 'configuration' | 'token' | 'product_search';

type KrogerDiagnosticRecord = {
  ok: boolean;
  query: string;
  generatedAt: string;
  stage: KrogerDiagnosticStage;
  outputFilePath: string;
  normalizedOutputFilePath: string;
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
  products?: NormalizedKrogerProduct[];
  error?: {
    message: string;
    code: string;
  };
};

export type NormalizedKrogerProduct = KrogerProductSearchResult;

export type KrogerProductDiagnosticSummary = {
  ok: boolean;
  query: string;
  generatedAt: string;
  stage: KrogerDiagnosticStage;
  outputFilePath: string;
  normalizedOutputFilePath: string;
  tokenStatusCode?: number;
  productStatusCode?: number;
  products: NormalizedKrogerProduct[];
  error?: string;
};

export type KrogerProductDiagnosticRunner = (query?: string) => Promise<KrogerProductDiagnosticSummary>;

type KrogerLookupOptions = {
  query?: string;
  fetchImpl?: typeof fetch;
};

type KrogerListingContext = {
  storeId: number;
  storeName: string;
  locationId: string;
  checkedAt: string;
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

export async function lookupAndWriteKrogerProductResponse(
  config: AppConfig,
  options: KrogerLookupOptions = {},
): Promise<KrogerProductDiagnosticSummary> {
  const query = normalizeProductQuery(options.query);
  const outputFilePath = config.kroger.productResponseFilePath;
  const normalizedOutputFilePath = config.kroger.normalizedProductResponseFilePath;
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
      normalizedOutputFilePath,
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
  const productURL = krogerProductSearchURL(config, query);

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
      normalizedOutputFilePath,
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
      normalizedOutputFilePath,
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
    const products = productResponse.ok
      ? normalizeKrogerProducts(productResponse.body, krogerListingContext(config, new Date().toISOString()))
      : [];
    const record = createDiagnosticRecord({
      ok: productResponse.ok,
      query,
      outputFilePath,
      normalizedOutputFilePath,
      stage: 'product_search',
      tokenRequest,
      tokenResponse: tokenResult.response,
      productRequest: {
        method: 'GET',
        url: productURL.toString(),
      },
      productResponse,
      products,
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
    await writeNormalizedProductResponse(record);
    return summarizeDiagnosticRecord(record);
  } catch (error) {
    const record = createDiagnosticRecord({
      ok: false,
      query,
      outputFilePath,
      normalizedOutputFilePath,
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

export function normalizeKrogerProducts(
  productResponseBody: unknown,
  context?: KrogerListingContext,
): NormalizedKrogerProduct[] {
  if (!isRecord(productResponseBody) || !Array.isArray(productResponseBody.data)) {
    return [];
  }

  return productResponseBody.data
    .filter(isRecord)
    .map((product) => {
      const description = stringValue(product.description);
      const productId = stringValue(product.productId);
      const upc = stringValue(product.upc);
      const productPageURI = stringValue(product.productPageURI);
      const brand = stringValue(product.brand);
      const image = featuredLargeImageURL(product.images);
      const aisles = Array.isArray(product.aisleLocations) ? product.aisleLocations : [];
      const firstItem = Array.isArray(product.items) ? product.items.find(isRecord) : undefined;

      return {
        productId,
        upc,
        productPageURI,
        aisles,
        brand,
        name: description,
        description,
        image,
        storeListings: context
          ? [
              krogerStoreListing({
                context,
                productId,
                upc,
                productPageURI,
                brand,
                description,
                image,
                aisles,
                firstItem,
              }),
            ]
          : [],
      };
    });
}

function normalizeProductQuery(value: string | undefined): string {
  const trimmed = value?.trim();
  return trimmed ? trimmed : DEFAULT_PRODUCT_QUERY;
}

function krogerProductSearchURL(config: AppConfig, query: string): URL {
  const productURL = krogerURL(config.kroger.apiBaseURL, 'products');
  productURL.searchParams.set('filter.term', query);
  productURL.searchParams.set('filter.limit', String(config.kroger.productSearchLimit));

  if (config.kroger.locationId) {
    productURL.searchParams.set('filter.locationId', config.kroger.locationId);
  }

  return productURL;
}

function krogerListingContext(config: AppConfig, checkedAt: string): KrogerListingContext {
  return {
    storeId: config.kroger.shoppingStoreId,
    storeName: config.kroger.shoppingStoreName,
    locationId: config.kroger.locationId,
    checkedAt,
  };
}

function krogerStoreListing(options: {
  context: KrogerListingContext;
  productId: string | null;
  upc: string | null;
  productPageURI: string | null;
  brand: string | null;
  description: string | null;
  image: string | null;
  aisles: unknown[];
  firstItem?: Record<string, unknown>;
}): ShoppingItemStoreListing {
  const firstAisle = options.aisles.find(isRecord);
  const price = isRecord(options.firstItem?.price) ? options.firstItem.price : undefined;
  const inventory = isRecord(options.firstItem?.inventory) ? options.firstItem.inventory : undefined;
  const listing: ShoppingItemStoreListing = {
    storeId: options.context.storeId,
    storeName: options.context.storeName,
    krogerLocationId: options.context.locationId,
    product: {
      ...(options.productId ? { productId: options.productId } : {}),
      ...(options.upc ? { upc: options.upc } : {}),
      ...(options.productPageURI ? { productPageURI: options.productPageURI } : {}),
      ...(options.brand ? { brand: options.brand } : {}),
      ...(options.description ? { name: options.description, description: options.description } : {}),
      ...(options.image ? { image: options.image } : {}),
    },
    ...(firstAisle ? { aisle: krogerAisle(firstAisle) } : {}),
    ...(price ? { price: krogerPrice(price) } : {}),
    ...(inventory ? { inventory } : {}),
  };

  return listing;
}

function krogerAisle(aisle: Record<string, unknown>): NonNullable<ShoppingItemStoreListing['aisle']> {
  const number = stringValue(aisle.number);
  const description = stringValue(aisle.description);
  const shelfNumber = stringValue(aisle.shelfNumber);
  const displayParts = [number, shelfNumber].filter((value): value is string => Boolean(value));

  return {
    ...(displayParts.length > 0 ? { display: displayParts.join(':') } : {}),
    ...(description ? { description } : {}),
    ...(number ? { number } : {}),
    ...(shelfNumber ? { shelfNumber } : {}),
    raw: aisle,
  };
}

function krogerPrice(price: Record<string, unknown>): NonNullable<ShoppingItemStoreListing['price']> {
  const regular = numberValue(price.regular);
  const promo = numberValue(price.promo);

  return {
    ...(regular !== undefined ? { regular } : {}),
    ...(promo !== undefined ? { promo } : {}),
  };
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

async function writeNormalizedProductResponse(record: KrogerDiagnosticRecord): Promise<void> {
  const normalizedResponse = {
    ok: record.ok,
    query: record.query,
    generatedAt: record.generatedAt,
    products: record.products ?? [],
    ...(record.error ? { error: record.error } : {}),
  };

  await mkdir(path.dirname(record.normalizedOutputFilePath), { recursive: true });
  await writeFile(record.normalizedOutputFilePath, `${JSON.stringify(normalizedResponse, null, 2)}\n`, 'utf8');
}

function summarizeDiagnosticRecord(record: KrogerDiagnosticRecord): KrogerProductDiagnosticSummary {
  return {
    ok: record.ok,
    query: record.query,
    generatedAt: record.generatedAt,
    stage: record.stage,
    outputFilePath: record.outputFilePath,
    normalizedOutputFilePath: record.normalizedOutputFilePath,
    tokenStatusCode: record.tokenResponse?.status,
    productStatusCode: record.productResponse?.status,
    products: record.products ?? [],
    error: record.error?.message,
  };
}

function featuredLargeImageURL(value: unknown): string | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const featuredImage = value.filter(isRecord).find((image) => image.featured === true);

  if (!featuredImage || !Array.isArray(featuredImage.sizes)) {
    return null;
  }

  const largeSize = featuredImage.sizes
    .filter(isRecord)
    .find((size) => size.size === 'large');

  if (typeof largeSize?.url === 'string') {
    return largeSize.url;
  }

  const fallbackSize = featuredImage.sizes[1];

  return isRecord(fallbackSize) && typeof fallbackSize.url === 'string' ? fallbackSize.url : null;
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value : null;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim()) {
    const parsed = Number(value);

    return Number.isFinite(parsed) ? parsed : undefined;
  }

  return undefined;
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
