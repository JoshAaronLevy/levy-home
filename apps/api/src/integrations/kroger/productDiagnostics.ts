import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

import type { AppConfig } from '../../config.js';
import {
  errorMessage,
  KROGER_PRODUCT_SCOPE,
  krogerListingContext,
  krogerProductSearchURL,
  krogerURL,
  normalizeProductQuery,
  requestKrogerProducts,
  requestKrogerToken,
  type KrogerDiagnosticError,
  type KrogerLookupOptions,
  type KrogerProductResponse,
  type KrogerTokenResponse,
} from './productClient.js';
import {
  normalizeKrogerProducts,
  type NormalizedKrogerProduct,
} from './productNormalizer.js';

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
  tokenResponse?: KrogerTokenResponse;
  productRequest?: {
    method: 'GET';
    url: string;
  };
  productResponse?: KrogerProductResponse;
  products?: NormalizedKrogerProduct[];
  error?: KrogerDiagnosticError;
};

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

  let tokenResult: Awaited<ReturnType<typeof requestKrogerToken>>;

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
