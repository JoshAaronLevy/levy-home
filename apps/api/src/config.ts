import path from 'node:path';
import { fileURLToPath } from 'node:url';

import type { LightGroupStatus } from './contracts.js';

export type HomeAssistantMode = 'mock' | 'live';
export type APNsDefaultEnvironment = 'sandbox' | 'production';

export type CuratedLightGroup = Pick<LightGroupStatus, 'id' | 'name'> & {
  entityId: string;
};

export type CuratedLightEntity = Pick<LightGroupStatus, 'id' | 'name'> & {
  entityId: string;
};

export type TrackedPhoneEntity = {
  entityId: string;
  person: string;
  deviceName?: string;
};

export type TrackedPhoneEntityPattern = {
  pattern: string;
  person: string;
  deviceName?: string;
};

export type AppConfig = {
  port: number;
  haWebhookSecret?: string;
  kroger: {
    clientId?: string;
    clientSecret?: string;
    apiBaseURL: string;
    productResponseFilePath: string;
    productSearchLimit: number;
  };
  apns: {
    keyId?: string;
    teamId?: string;
    bundleId?: string;
    privateKey?: string;
    privateKeyPath?: string;
    defaultEnvironment: APNsDefaultEnvironment;
  };
  homeAssistant: {
    mode: HomeAssistantMode;
    baseURL?: string;
    token?: string;
    garageCoverEntityId: string;
    allLightsEntityId: string;
    lightGroups: CuratedLightGroup[];
    lightEntities: CuratedLightEntity[];
    mockTotalLightCount: number;
    activity: {
      isEnabled: boolean;
      webSocketURL?: string;
      trackedPhoneEntities: TrackedPhoneEntity[];
      trackedPhoneEntityPatterns: TrackedPhoneEntityPattern[];
    };
  };
};

export function readConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return {
    port: readNumber(env.PORT, 4000),
    haWebhookSecret: readOptionalString(env.LEVY_HOME_HA_WEBHOOK_SECRET),
    kroger: {
      clientId: readOptionalString(env.KROGER_CLIENT_ID),
      clientSecret: readOptionalString(env.KROGER_CLIENT_SECRET),
      apiBaseURL: readOptionalString(env.KROGER_API_BASE_URL) ?? 'https://api.kroger.com/v1',
      productResponseFilePath:
        readOptionalString(env.KROGER_PRODUCT_RESPONSE_PATH) ??
        path.join(API_PACKAGE_ROOT, 'kroger-product-response.json'),
      productSearchLimit: clampNumber(readNumber(env.KROGER_PRODUCT_SEARCH_LIMIT, 10), 1, 50),
    },
    apns: {
      keyId: readOptionalString(env.APNS_KEY_ID),
      teamId: readOptionalString(env.APNS_TEAM_ID),
      bundleId: readOptionalString(env.APNS_BUNDLE_ID) ?? 'com.levyhome.app',
      privateKey: readOptionalString(env.APNS_PRIVATE_KEY)?.replace(/\\n/g, '\n'),
      privateKeyPath: readOptionalString(env.APNS_PRIVATE_KEY_PATH),
      defaultEnvironment: readAPNsDefaultEnvironment(env.APNS_ENVIRONMENT),
    },
    homeAssistant: {
      mode: readHomeAssistantMode(env.HOME_ASSISTANT_MODE),
      baseURL: readOptionalString(env.HOME_ASSISTANT_BASE_URL),
      token: readOptionalString(env.HOME_ASSISTANT_TOKEN),
      garageCoverEntityId: readOptionalString(env.HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID) ?? 'cover.main_garage_door',
      allLightsEntityId: readOptionalString(env.HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID) ?? 'light.all_lights',
      lightGroups: readLightGroups(env.HOME_ASSISTANT_LIGHT_GROUPS),
      lightEntities: readLightEntities(env.HOME_ASSISTANT_LIGHT_ENTITIES),
      mockTotalLightCount: readNumber(env.MOCK_TOTAL_LIGHT_COUNT, 12),
      activity: {
        isEnabled: readBoolean(env.HOME_ASSISTANT_ACTIVITY_ENABLED, false, 'HOME_ASSISTANT_ACTIVITY_ENABLED'),
        webSocketURL: readOptionalString(env.HOME_ASSISTANT_WEBSOCKET_URL),
        trackedPhoneEntities: readTrackedPhoneEntities(env.HOME_ASSISTANT_PHONE_ENTITIES),
        trackedPhoneEntityPatterns: readTrackedPhoneEntityPatterns(env.HOME_ASSISTANT_PHONE_ENTITY_PATTERNS),
      },
    },
  };
}

const API_PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function readAPNsDefaultEnvironment(value: string | undefined): APNsDefaultEnvironment {
  return value === 'production' ? 'production' : 'sandbox';
}

function readHomeAssistantMode(value: string | undefined): HomeAssistantMode {
  return value === 'live' ? 'live' : 'mock';
}

function readNumber(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function readBoolean(value: string | undefined, fallback: boolean, envName: string): boolean {
  const normalized = readOptionalString(value)?.toLowerCase();

  if (!normalized) {
    return fallback;
  }

  if (['1', 'true', 'yes', 'on'].includes(normalized)) {
    return true;
  }

  if (['0', 'false', 'no', 'off'].includes(normalized)) {
    return false;
  }

  throw new Error(`Invalid ${envName} value: expected true or false.`);
}

function readOptionalString(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function readLightGroups(value: string | undefined): CuratedLightGroup[] {
  const rawGroups = readOptionalString(value);

  if (!rawGroups) {
    return [];
  }

  return rawGroups
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [id, name, entityId] = entry.split(':').map((part) => part.trim());

      if (!id || !name || !entityId) {
        throw new Error(`Invalid HOME_ASSISTANT_LIGHT_GROUPS entry: ${entry}`);
      }

      return { id, name, entityId };
    });
}

function readLightEntities(value: string | undefined): CuratedLightEntity[] {
  const rawEntities = readOptionalString(value);

  if (!rawEntities) {
    return [];
  }

  return rawEntities
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const separatorIndex = entry.indexOf(':');

      if (separatorIndex === -1) {
        throw new Error(`Invalid HOME_ASSISTANT_LIGHT_ENTITIES entry: ${entry}`);
      }

      const entityId = entry.slice(0, separatorIndex).trim();
      const name = entry.slice(separatorIndex + 1).trim();

      if (!entityId || !name) {
        throw new Error(`Invalid HOME_ASSISTANT_LIGHT_ENTITIES entry: ${entry}`);
      }

      return {
        id: lightEntityIdToTargetId(entityId),
        name,
        entityId,
      };
    });
}

function readTrackedPhoneEntities(value: string | undefined): TrackedPhoneEntity[] {
  const rawEntities = readOptionalString(value);

  if (!rawEntities) {
    return [];
  }

  return rawEntities
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [entityId, person, ...deviceNameParts] = entry.split(':').map((part) => part.trim());
      const deviceName = readOptionalString(deviceNameParts.join(':'));

      if (!entityId || !person || !isHomeAssistantEntityId(entityId)) {
        throw new Error(`Invalid HOME_ASSISTANT_PHONE_ENTITIES entry: ${entry}`);
      }

      return {
        entityId,
        person,
        ...(deviceName ? { deviceName } : {}),
      };
    });
}

function readTrackedPhoneEntityPatterns(value: string | undefined): TrackedPhoneEntityPattern[] {
  const rawPatterns = readOptionalString(value);

  if (!rawPatterns) {
    return [];
  }

  return rawPatterns
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [pattern, person, ...deviceNameParts] = entry.split(':').map((part) => part.trim());
      const deviceName = readOptionalString(deviceNameParts.join(':'));

      if (!pattern || !person || !isHomeAssistantEntityPattern(pattern)) {
        throw new Error(`Invalid HOME_ASSISTANT_PHONE_ENTITY_PATTERNS entry: ${entry}`);
      }

      return {
        pattern,
        person,
        ...(deviceName ? { deviceName } : {}),
      };
    });
}

function lightEntityIdToTargetId(entityId: string): string {
  return entityId
    .replace(/^[^.]+\./, '')
    .replace(/[^a-zA-Z0-9_]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function isHomeAssistantEntityId(value: string): boolean {
  return /^[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+$/.test(value);
}

function isHomeAssistantEntityPattern(value: string): boolean {
  return /^[a-zA-Z0-9_*]+\.[a-zA-Z0-9_*]+$/.test(value);
}
