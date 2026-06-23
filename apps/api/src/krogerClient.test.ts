import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import type { AppConfig } from './config.js';
import { lookupAndWriteKrogerProductResponse } from './krogerClient.js';

test('lookupAndWriteKrogerProductResponse fetches a token, searches products, and writes the Kroger response', async () => {
  const tempDir = await mkdtemp(path.join(tmpdir(), 'levy-home-kroger-'));
  const outputFilePath = path.join(tempDir, 'kroger-product-response.json');
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

    if (url === 'https://api.kroger.test/v1/products?filter.term=Soy+Milk&filter.limit=10') {
      return new Response(
        JSON.stringify({
          data: [
            {
              productId: '0001111000001',
              description: 'Soy Milk',
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

    assert.equal(summary.ok, true);
    assert.equal(summary.productStatusCode, 200);
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
    kroger: {
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
      apiBaseURL: 'https://api.kroger.test/v1',
      productResponseFilePath: options.outputFilePath,
      productSearchLimit: 10,
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
