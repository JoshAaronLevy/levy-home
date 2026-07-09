import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import type { AppConfig } from '../../../../src/config.js';
import { lookupAndWriteKrogerProductResponse } from '../../../../src/integrations/kroger/productDiagnostics.js';

test('lookupAndWriteKrogerProductResponse fetches a token, searches products, and writes the Kroger response', async () => {
  const tempDir = await mkdtemp(path.join(tmpdir(), 'levy-home-kroger-'));
  const outputFilePath = path.join(tempDir, 'kroger-product-response.json');
  const normalizedOutputFilePath = path.join(tempDir, 'kroger-products-normalized.json');
  const requests: Array<{ url: string; init?: RequestInit }> = [];
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = requestURL(input);
    requests.push({ url, init });

    if (url === 'https://api.kroger.test/v1/connect/oauth2/token') {
      return new Response(
        JSON.stringify({
          access_token: 'secret-access-token',
          token_type: 'Bearer',
          expires_in: 1800,
          scope: 'product.compact',
        }),
        {
          status: 200,
          statusText: 'OK',
          headers: { 'Content-Type': 'application/json' },
        },
      );
    }

    if (url === 'https://api.kroger.test/v1/products?filter.term=Soy+Milk&filter.limit=10&filter.locationId=62000008') {
      return new Response(
        JSON.stringify({
          data: [
            {
              productId: '0001111000001',
              upc: '0001111000001',
              productPageURI: '/p/simple-truth-soy-milk/0001111000001',
              aisleLocations: [
                {
                  description: 'Baby',
                  number: '12',
                },
              ],
              brand: 'Simple Truth',
              description: 'Soy Milk',
              items: [
                {
                  itemId: '0001111000001',
                  inventory: {
                    stockLevel: 'LOW',
                  },
                  price: {
                    regular: 4.99,
                    promo: 3.99,
                    effectiveDate: {
                      value: '2026-06-10T17:33:40.553Z',
                    },
                  },
                },
              ],
              images: [
                {
                  perspective: 'front',
                  featured: true,
                  sizes: [
                    {
                      size: 'xlarge',
                      url: 'https://www.kroger.com/product/images/xlarge/front/0001111000001',
                    },
                    {
                      size: 'large',
                      url: 'https://www.kroger.com/product/images/large/front/0001111000001',
                    },
                  ],
                },
              ],
            },
          ],
        }),
        {
          status: 200,
          statusText: 'OK',
          headers: { 'Content-Type': 'application/json' },
        },
      );
    }

    return new Response(JSON.stringify({ error: 'Unexpected URL' }), { status: 404 });
  };

  try {
    const summary = await lookupAndWriteKrogerProductResponse(
      testConfig({ outputFilePath }),
      {
        query: 'Soy Milk',
        fetchImpl,
      },
    );
    const diagnostic = JSON.parse(await readFile(outputFilePath, 'utf8')) as Record<string, any>;
    const normalized = JSON.parse(await readFile(normalizedOutputFilePath, 'utf8')) as Record<string, any>;

    assert.equal(summary.ok, true);
    assert.equal(summary.productStatusCode, 200);
    assert.equal(summary.normalizedOutputFilePath, normalizedOutputFilePath);
    assert.equal(summary.products.length, 1);
    assert.equal(requests.length, 2);
    assert.equal(
      new Headers(requests[0].init?.headers).get('authorization'),
      `Basic ${Buffer.from('test-client-id:test-client-secret').toString('base64')}`,
    );
    assert.equal(String(requests[0].init?.body), 'grant_type=client_credentials&scope=product.compact');
    assert.equal(new Headers(requests[1].init?.headers).get('authorization'), 'Bearer secret-access-token');
    assert.equal(diagnostic.ok, true);
    assert.equal(diagnostic.query, 'Soy Milk');
    assert.equal(diagnostic.productResponse.body.data[0].description, 'Soy Milk');
    assert.deepEqual(diagnostic.products, [
      {
        productId: '0001111000001',
        upc: '0001111000001',
        productPageURI: '/p/simple-truth-soy-milk/0001111000001',
        aisles: [
          {
            description: 'Baby',
            number: '12',
          },
        ],
        brand: 'Simple Truth',
        name: 'Soy Milk',
        description: 'Soy Milk',
        image: 'https://www.kroger.com/product/images/large/front/0001111000001',
        storeListings: [
          {
            storeId: 2,
            storeName: 'King Soopers',
            krogerLocationId: '62000008',
            product: {
              productId: '0001111000001',
              upc: '0001111000001',
              productPageURI: '/p/simple-truth-soy-milk/0001111000001',
              brand: 'Simple Truth',
              name: 'Soy Milk',
              description: 'Soy Milk',
              image: 'https://www.kroger.com/product/images/large/front/0001111000001',
            },
            aisle: {
              display: '12',
              description: 'Baby',
              number: '12',
              raw: {
                description: 'Baby',
                number: '12',
              },
            },
            price: {
              regular: 4.99,
              promo: 3.99,
            },
            inventory: {
              stockLevel: 'LOW',
            },
          },
        ],
      },
    ]);
    assert.deepEqual(normalized.products, diagnostic.products);
    assert.equal(JSON.stringify(diagnostic).includes('secret-access-token'), false);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test('lookupAndWriteKrogerProductResponse writes a diagnostic failure when credentials are incomplete', async () => {
  const tempDir = await mkdtemp(path.join(tmpdir(), 'levy-home-kroger-'));
  const outputFilePath = path.join(tempDir, 'kroger-product-response.json');
  let fetchWasCalled = false;
  const fetchImpl: typeof fetch = async () => {
    fetchWasCalled = true;
    return new Response(null, { status: 500 });
  };

  try {
    const summary = await lookupAndWriteKrogerProductResponse(
      {
        ...testConfig({ outputFilePath }),
        kroger: {
          ...testConfig({ outputFilePath }).kroger,
          clientSecret: undefined,
        },
      },
      { fetchImpl },
    );
    const diagnostic = JSON.parse(await readFile(outputFilePath, 'utf8')) as Record<string, any>;

    assert.equal(summary.ok, false);
    assert.equal(summary.stage, 'configuration');
    assert.equal(fetchWasCalled, false);
    assert.equal(diagnostic.error.code, 'missing_kroger_credentials');
    assert.match(diagnostic.error.message, /KROGER_CLIENT_SECRET/);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

function testConfig(options: { outputFilePath: string }): AppConfig {
  return {
    port: 0,
    weatherAlerts: {
      isEnabled: false,
      latitude: 39.5388289,
      longitude: -105.0305231,
      timeZone: 'America/Denver',
      forecastBaseURL: 'https://api.open-meteo.test/v1/forecast',
      pollIntervalMinutes: 30,
      leadTimeMinutes: 60,
      eventSeparationMinutes: 180,
    },
    kroger: {
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
      apiBaseURL: 'https://api.kroger.test/v1',
      productResponseFilePath: options.outputFilePath,
      normalizedProductResponseFilePath: path.join(path.dirname(options.outputFilePath), 'kroger-products-normalized.json'),
      productSearchLimit: 10,
      locationId: '62000008',
      shoppingStoreId: 2,
      shoppingStoreName: 'King Soopers',
    },
    apns: {
      bundleId: 'com.levyhome.app',
      defaultEnvironment: 'sandbox',
    },
    homeAssistant: {
      mode: 'mock',
      garageCoverEntityId: 'cover.test_garage',
      allLightsEntityId: 'light.test_all_lights',
      lightGroups: [],
      lightEntities: [],
      mockTotalLightCount: 12,
      activity: {
        isEnabled: false,
        trackedPhoneEntities: [],
        trackedPhoneEntityPatterns: [],
      },
    },
  };
}

function requestURL(input: Parameters<typeof fetch>[0]): string {
  if (typeof input === 'string') {
    return input;
  }

  if (input instanceof URL) {
    return input.toString();
  }

  return input.url;
}
