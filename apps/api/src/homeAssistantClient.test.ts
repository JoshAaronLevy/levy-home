import assert from 'node:assert/strict';
import { createServer, type IncomingMessage, type RequestListener, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { test } from 'node:test';

import type { AppConfig } from './config.js';
import { createHomeAssistantFacade } from './homeAssistantClient.js';

test('live Home Assistant facade opens and closes the configured garage cover', async () => {
  const serviceCalls: Array<{ path: string; body: unknown }> = [];
  const server = await startHomeAssistantServer(async (req, res) => {
    if (!req.url?.startsWith('/api/services/cover/')) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    serviceCalls.push({
      path: req.url,
      body: await readJSONBody(req),
    });

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify([]));
  });

  try {
    const facade = createHomeAssistantFacade(liveConfig(server.baseURL));

    await facade.openGarage();
    await facade.closeGarage();

    assert.deepEqual(serviceCalls, [
      {
        path: '/api/services/cover/open_cover',
        body: { entity_id: 'cover.meross_garage_door' },
      },
      {
        path: '/api/services/cover/close_cover',
        body: { entity_id: 'cover.meross_garage_door' },
      },
    ]);
  } finally {
    await server.close();
  }
});

test('live Home Assistant facade returns per-person device tracker presence', async () => {
  const states = new Map<string, unknown>([
    [
      '/api/states/device_tracker.josh_iphone',
      {
        entity_id: 'device_tracker.josh_iphone',
        state: 'not_home',
        last_updated: '2026-06-20T18:00:00.000Z',
      },
    ],
    [
      '/api/states/device_tracker.mallorys_iphone',
      {
        entity_id: 'device_tracker.mallorys_iphone',
        state: 'home',
        last_updated: '2026-06-20T18:01:00.000Z',
      },
    ],
  ]);
  const server = await startHomeAssistantServer(async (req, res) => {
    const state = req.url ? states.get(req.url) : undefined;

    if (!state) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Not found' }));
      return;
    }

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(state));
  });

  try {
    const facade = createHomeAssistantFacade({
      ...liveConfig(server.baseURL),
      homeAssistant: {
        ...liveConfig(server.baseURL).homeAssistant,
        activity: {
          isEnabled: true,
          trackedPhoneEntityPatterns: [],
          trackedPhoneEntities: [
            { entityId: 'sensor.josh_iphone_battery_level', person: 'Josh', deviceName: "Joshs iPhone" },
            { entityId: 'device_tracker.josh_iphone', person: 'Josh', deviceName: "Joshs iPhone" },
            { entityId: 'device_tracker.josh_watch', person: 'Josh', deviceName: 'Josh Watch' },
            { entityId: 'device_tracker.mallorys_iphone', person: 'Mallory', deviceName: "Mallorys iPhone" },
          ],
        },
      },
    });

    const presence = await facade.getPresenceStatuses();

    assert.deepEqual(presence, [
      {
        person: 'Josh',
        state: 'away',
        entityId: 'device_tracker.josh_iphone',
        deviceName: "Joshs iPhone",
        lastUpdatedAt: '2026-06-20T18:00:00.000Z',
        isStale: false,
      },
      {
        person: 'Mallory',
        state: 'home',
        entityId: 'device_tracker.mallorys_iphone',
        deviceName: "Mallorys iPhone",
        lastUpdatedAt: '2026-06-20T18:01:00.000Z',
        isStale: false,
      },
    ]);
  } finally {
    await server.close();
  }
});

function liveConfig(baseURL: string): AppConfig {
  return {
    port: 0,
    kroger: {
      apiBaseURL: 'https://api.kroger.test/v1',
      productResponseFilePath: '/tmp/kroger-product-response.json',
      normalizedProductResponseFilePath: '/tmp/kroger-products-normalized.json',
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
      mode: 'live',
      baseURL,
      token: 'test-home-assistant-token',
      garageCoverEntityId: 'cover.meross_garage_door',
      allLightsEntityId: 'light.all_lights',
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

async function startHomeAssistantServer(
  handler: RequestListener,
): Promise<{ baseURL: string; close: () => Promise<void> }> {
  const server: Server = createServer((req, res) => {
    if (req.headers.authorization !== 'Bearer test-home-assistant-token') {
      res.writeHead(401, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Unauthorized' }));
      return;
    }

    void handler(req, res);
  });

  await new Promise<void>((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve();
    });
  });

  const address = server.address() as AddressInfo;

  return {
    baseURL: `http://127.0.0.1:${address.port}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        });
      }),
  };
}

async function readJSONBody(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];

  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }

  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
