import assert from 'node:assert/strict';
import { beforeEach, test } from 'node:test';

import type { AppConfig } from '../../../../src/config.js';
import {
  createHomeAssistantActivityListener,
  resolveHomeAssistantWebSocketURL,
  shouldStartHomeAssistantActivityListener,
  type HomeAssistantStateChangedEvent,
} from '../../../../src/integrations/homeAssistant/activityListener.js';

type FakeWebSocketListener = (() => void) | ((event: { data: unknown }) => void) | ((event: unknown) => void);

const baseConfig: AppConfig = {
  port: 0,
  haWebhookSecret: 'test-secret',
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
    baseURL: 'https://home.example.test',
    token: 'test-home-assistant-token',
    garageCoverEntityId: 'cover.test_garage',
    thermostatClimateEntityId: 'climate.test_thermostat',
    allLightsEntityId: 'light.test_all_lights',
    lightGroups: [],
    lightEntities: [],
    camera: {
      id: 'kids_room',
      displayName: 'Kids Room',
      entityId: 'camera.kids_room',
      speakerVolumeEntityId: 'number.kids_room_speaker_volume',
      accessToken: 'test-camera-access-token',
    },
    mockTotalLightCount: 12,
    activity: {
      isEnabled: true,
      trackedPhoneEntities: [
        {
          entityId: 'sensor.josh_iphone_battery_level',
          person: 'Josh',
          deviceName: "Joshs iPhone",
        },
      ],
      trackedPhoneEntityPatterns: [
        {
          pattern: 'sensor.iphone_*',
          person: 'Mallory',
          deviceName: "Mallorys iPhone",
        },
      ],
    },
  },
};

class FakeWebSocket {
  static instances: FakeWebSocket[] = [];

  readonly sentMessages: Array<Record<string, unknown>> = [];
  private readonly listeners = new Map<string, FakeWebSocketListener[]>();

  constructor(readonly url: string) {
    FakeWebSocket.instances.push(this);
  }

  addEventListener(type: 'open', listener: () => void): void;
  addEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  addEventListener(type: 'close', listener: () => void): void;
  addEventListener(type: 'error', listener: (event: unknown) => void): void;
  addEventListener(
    type: string,
    listener: FakeWebSocketListener,
  ): void {
    const listeners = this.listeners.get(type) ?? [];
    listeners.push(listener);
    this.listeners.set(type, listeners);
  }

  send(data: string): void {
    this.sentMessages.push(JSON.parse(data) as Record<string, unknown>);
  }

  close(): void {
    this.emitClose();
  }

  emitMessage(message: Record<string, unknown>): void {
    this.emit('message', { data: JSON.stringify(message) });
  }

  emitClose(): void {
    this.emit('close');
  }

  private emit(type: string, event?: { data: unknown }): void {
    for (const listener of this.listeners.get(type) ?? []) {
      if (event) {
        (listener as (event: { data: unknown }) => void)(event);
      } else {
        (listener as () => void)();
      }
    }
  }
}

beforeEach(() => {
  FakeWebSocket.instances = [];
});

test('shouldStartHomeAssistantActivityListener requires live mode and enabled activity', () => {
  assert.equal(shouldStartHomeAssistantActivityListener(baseConfig), true);
  assert.equal(
    shouldStartHomeAssistantActivityListener({
      ...baseConfig,
      homeAssistant: {
        ...baseConfig.homeAssistant,
        mode: 'mock',
      },
    }),
    false,
  );
  assert.equal(
    shouldStartHomeAssistantActivityListener({
      ...baseConfig,
      homeAssistant: {
        ...baseConfig.homeAssistant,
        activity: {
          ...baseConfig.homeAssistant.activity,
          isEnabled: false,
        },
      },
    }),
    false,
  );
});

test('resolveHomeAssistantWebSocketURL derives ws/wss URLs and honors explicit overrides', () => {
  assert.equal(resolveHomeAssistantWebSocketURL(baseConfig), 'wss://home.example.test/api/websocket');
  assert.equal(
    resolveHomeAssistantWebSocketURL({
      ...baseConfig,
      homeAssistant: {
        ...baseConfig.homeAssistant,
        baseURL: 'http://homeassistant.local:8123',
      },
    }),
    'ws://homeassistant.local:8123/api/websocket',
  );
  assert.equal(
    resolveHomeAssistantWebSocketURL({
      ...baseConfig,
      homeAssistant: {
        ...baseConfig.homeAssistant,
        activity: {
          ...baseConfig.homeAssistant.activity,
          webSocketURL: 'wss://override.example.test/api/websocket',
        },
      },
    }),
    'wss://override.example.test/api/websocket',
  );
});

test('listener authenticates and subscribes to state_changed events', () => {
  const listener = createHomeAssistantActivityListener(baseConfig, {
    WebSocketImpl: FakeWebSocket,
    logger: silentLogger(),
  });

  listener?.start();
  const socket = FakeWebSocket.instances[0];

  assert.equal(socket.url, 'wss://home.example.test/api/websocket');

  socket.emitMessage({ type: 'auth_required' });
  socket.emitMessage({ type: 'auth_ok' });
  socket.emitMessage({ id: 1, type: 'result', success: true, result: null });

  assert.deepEqual(socket.sentMessages, [
    {
      type: 'auth',
      access_token: 'test-home-assistant-token',
    },
    {
      id: 1,
      type: 'subscribe_events',
      event_type: 'state_changed',
    },
  ]);
});

test('listener filters state_changed events to configured phone entities and patterns', () => {
  const receivedEvents: HomeAssistantStateChangedEvent[] = [];
  const listener = createHomeAssistantActivityListener(baseConfig, {
    WebSocketImpl: FakeWebSocket,
    logger: silentLogger(),
    onStateChanged: (event) => {
      receivedEvents.push(event);
    },
  });

  listener?.start();
  const socket = FakeWebSocket.instances[0];

  socket.emitMessage(stateChangedMessage('light.kitchen', 'off', 'on'));
  socket.emitMessage(stateChangedMessage('sensor.josh_iphone_battery_level', '82', '81'));
  socket.emitMessage(stateChangedMessage('sensor.iphone_activity', 'Stationary', 'Walking'));

  assert.equal(receivedEvents.length, 2);
  assert.equal(receivedEvents[0].entityId, 'sensor.josh_iphone_battery_level');
  assert.equal(receivedEvents[0].person, 'Josh');
  assert.equal(receivedEvents[0].deviceName, "Joshs iPhone");
  assert.equal(receivedEvents[0].oldState, '82');
  assert.equal(receivedEvents[0].newState, '81');
  assert.equal(receivedEvents[1].entityId, 'sensor.iphone_activity');
  assert.equal(receivedEvents[1].person, 'Mallory');
});

test('listener schedules reconnects after unexpected close', () => {
  const scheduledDelays: number[] = [];
  const callbacks: Array<() => void> = [];
  const listener = createHomeAssistantActivityListener(baseConfig, {
    WebSocketImpl: FakeWebSocket,
    logger: silentLogger(),
    reconnectDelaysMs: [10, 20],
    setTimeoutFn: ((callback: () => void, delay: number) => {
      callbacks.push(callback);
      scheduledDelays.push(delay);
      return callbacks.length as unknown as ReturnType<typeof setTimeout>;
    }) as typeof setTimeout,
    clearTimeoutFn: (() => undefined) as typeof clearTimeout,
  });

  listener?.start();
  FakeWebSocket.instances[0].emitClose();

  assert.deepEqual(scheduledDelays, [10]);

  callbacks[0]();
  assert.equal(FakeWebSocket.instances.length, 2);
});

test('listener stops instead of reconnecting after auth_invalid', () => {
  const scheduledDelays: number[] = [];
  const listener = createHomeAssistantActivityListener(baseConfig, {
    WebSocketImpl: FakeWebSocket,
    logger: silentLogger(),
    reconnectDelaysMs: [10],
    setTimeoutFn: ((_callback: () => void, delay: number) => {
      scheduledDelays.push(delay);
      return 1 as unknown as ReturnType<typeof setTimeout>;
    }) as typeof setTimeout,
    clearTimeoutFn: (() => undefined) as typeof clearTimeout,
  });

  listener?.start();
  FakeWebSocket.instances[0].emitMessage({ type: 'auth_invalid', message: 'Invalid token' });

  assert.deepEqual(scheduledDelays, []);
});

function stateChangedMessage(entityId: string, oldState: string, newState: string): Record<string, unknown> {
  return {
    id: 1,
    type: 'event',
    event: {
      event_type: 'state_changed',
      time_fired: '2026-06-15T17:00:00.000Z',
      data: {
        entity_id: entityId,
        old_state: {
          entity_id: entityId,
          state: oldState,
          attributes: {
            friendly_name: entityId,
          },
        },
        new_state: {
          entity_id: entityId,
          state: newState,
          attributes: {
            friendly_name: entityId,
          },
        },
      },
    },
  };
}

function silentLogger(): Pick<Console, 'info' | 'warn' | 'error'> {
  return {
    info: () => undefined,
    warn: () => undefined,
    error: () => undefined,
  };
}
