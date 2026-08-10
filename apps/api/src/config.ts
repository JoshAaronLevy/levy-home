import path from 'node:path';
import { fileURLToPath } from 'node:url';

import type { LightGroupStatus } from './contracts.js';
import {
  loadApnsPrivateKey,
  type APNsPrivateKeySource,
} from './integrations/apple/privateKey.js';

export type HomeAssistantMode = 'mock' | 'live';
export type APNsDefaultEnvironment = 'sandbox' | 'production';

export type CuratedLightGroup = Pick<LightGroupStatus, 'id' | 'name'> & {
  entityId: string;
};

export type CuratedLightEntity = Pick<LightGroupStatus, 'id' | 'name'> & {
  entityId: string;
};

export type RoomTemperatureSensorID =
  | 'study'
  | 'kitchen_family'
  | 'nursery'
  | 'master_bedroom'
  | 'playroom';

export type CuratedRoomTemperatureSensor = {
  id: RoomTemperatureSensorID;
  name: string;
  entityId: string;
};

export const defaultRoomTemperatureSensors: CuratedRoomTemperatureSensor[] = [
  { id: 'study', name: 'Study', entityId: 'sensor.study_thermometer_study_temperature' },
  { id: 'kitchen_family', name: 'Kitchen / Family', entityId: 'sensor.study_govee_thermometer_study_temperature' },
  { id: 'nursery', name: 'Nursery', entityId: 'sensor.nursery_thermometer_nursery_temperature' },
  { id: 'master_bedroom', name: 'Master Bedroom', entityId: 'sensor.master_bedroom_thermometer_master_bedroom_temperature' },
  { id: 'playroom', name: 'Playroom', entityId: 'sensor.playroom_thermometer_playroom_temperature' },
];

export type CuratedCamera = {
  id: 'kids_room';
  displayName: string;
  entityId: string;
  speakerVolumeEntityId: string;
  accessToken?: string;
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
  weatherAlerts: {
    isEnabled: boolean;
    latitude: number;
    longitude: number;
    timeZone: string;
    forecastBaseURL: string;
    pollIntervalMinutes: number;
    leadTimeMinutes: number;
    eventSeparationMinutes: number;
  };
  kroger: {
    clientId?: string;
    clientSecret?: string;
    apiBaseURL: string;
    productResponseFilePath: string;
    normalizedProductResponseFilePath: string;
    productSearchLimit: number;
    locationId: string;
    shoppingStoreId: number;
    shoppingStoreName: string;
  };
  apns: {
    keyId?: string;
    teamId?: string;
    bundleId?: string;
    privateKey?: string;
    privateKeySource?: APNsPrivateKeySource;
    privateKeyPath?: string;
    privateKeyLoadError?: string;
    inlinePrivateKeyIgnored?: boolean;
    defaultEnvironment: APNsDefaultEnvironment;
  };
  homeAssistant: {
    mode: HomeAssistantMode;
    baseURL?: string;
    token?: string;
    garageCoverEntityId: string;
    thermostatClimateEntityId: string;
    roomTemperatureSensors?: CuratedRoomTemperatureSensor[];
    allLightsEntityId?: string;
    lightGroups: CuratedLightGroup[];
    lightEntities: CuratedLightEntity[];
    camera: CuratedCamera;
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
  const privateKey = loadApnsPrivateKey(env);
  const homeAssistantMode = readHomeAssistantMode(env.HOME_ASSISTANT_MODE);

  return {
    port: readNumber(env.PORT, 4000),
    haWebhookSecret: readOptionalString(env.LEVY_HOME_HA_WEBHOOK_SECRET),
    weatherAlerts: {
      isEnabled: readBoolean(env.WEATHER_ALERTS_ENABLED, false, 'WEATHER_ALERTS_ENABLED'),
      latitude: readNumber(env.WEATHER_ALERTS_LATITUDE, 39.5388289),
      longitude: readNumber(env.WEATHER_ALERTS_LONGITUDE, -105.0305231),
      timeZone: readOptionalString(env.WEATHER_ALERTS_TIME_ZONE) ?? 'America/Denver',
      forecastBaseURL: readOptionalString(env.WEATHER_ALERTS_FORECAST_BASE_URL) ?? 'https://api.open-meteo.com/v1/forecast',
      pollIntervalMinutes: clampNumber(readNumber(env.WEATHER_ALERTS_POLL_INTERVAL_MINUTES, 30), 5, 180),
      leadTimeMinutes: clampNumber(readNumber(env.WEATHER_ALERTS_LEAD_TIME_MINUTES, 60), 15, 360),
      eventSeparationMinutes: clampNumber(readNumber(env.WEATHER_ALERTS_EVENT_SEPARATION_MINUTES, 180), 30, 720),
    },
    kroger: {
      clientId: readOptionalString(env.KROGER_CLIENT_ID),
      clientSecret: readOptionalString(env.KROGER_CLIENT_SECRET),
      apiBaseURL: readOptionalString(env.KROGER_API_BASE_URL) ?? 'https://api.kroger.com/v1',
      productResponseFilePath:
        readOptionalString(env.KROGER_PRODUCT_RESPONSE_PATH) ??
        path.join(API_PACKAGE_ROOT, 'kroger-product-response.json'),
      normalizedProductResponseFilePath:
        readOptionalString(env.KROGER_NORMALIZED_PRODUCT_RESPONSE_PATH) ??
        path.join(API_PACKAGE_ROOT, 'kroger-products-normalized.json'),
      productSearchLimit: clampNumber(readNumber(env.KROGER_PRODUCT_SEARCH_LIMIT, 50), 1, 50),
      locationId: readOptionalString(env.KROGER_LOCATION_ID) ?? '62000008',
      shoppingStoreId: readNumber(env.KROGER_SHOPPING_STORE_ID, 2),
      shoppingStoreName: readOptionalString(env.KROGER_SHOPPING_STORE_NAME) ?? 'King Soopers',
    },
    apns: {
      keyId: readOptionalString(env.APNS_KEY_ID),
      teamId: readOptionalString(env.APNS_TEAM_ID),
      bundleId: readOptionalString(env.APNS_BUNDLE_ID) ?? 'com.levyhome.app',
      ...(privateKey.privateKey ? { privateKey: privateKey.privateKey } : {}),
      privateKeySource: privateKey.source,
      ...(privateKey.path ? { privateKeyPath: privateKey.path } : {}),
      ...(privateKey.error ? { privateKeyLoadError: privateKey.error } : {}),
      inlinePrivateKeyIgnored: privateKey.inlineKeyIgnored,
      defaultEnvironment: readAPNsDefaultEnvironment(env.APNS_ENVIRONMENT),
    },
    homeAssistant: {
      mode: homeAssistantMode,
      baseURL: readOptionalString(env.HOME_ASSISTANT_BASE_URL),
      token: readOptionalString(env.HOME_ASSISTANT_TOKEN),
      garageCoverEntityId: readOptionalString(env.HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID) ?? 'cover.main_garage_door',
      thermostatClimateEntityId: readThermostatClimateEntityId(env.HOME_ASSISTANT_THERMOSTAT_CLIMATE_ENTITY_ID),
      roomTemperatureSensors: readRoomTemperatureSensors(env.HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS),
      allLightsEntityId: readOptionalString(env.HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID),
      lightGroups: readLightGroups(env.HOME_ASSISTANT_LIGHT_GROUPS),
      lightEntities: readLightEntities(env.HOME_ASSISTANT_LIGHT_ENTITIES),
      camera: readCameraConfig(env, homeAssistantMode === 'live'),
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

function readCameraConfig(env: NodeJS.ProcessEnv, requiresAccessToken: boolean): CuratedCamera {
  const entityId = readOptionalString(env.HOME_ASSISTANT_KIDS_ROOM_CAMERA_ENTITY_ID) ?? 'camera.kids_room';
  const speakerVolumeEntityId =
    readOptionalString(env.HOME_ASSISTANT_KIDS_ROOM_SPEAKER_VOLUME_ENTITY_ID) ?? 'number.kids_room_speaker_volume';
  const accessToken = readOptionalString(env.LEVY_HOME_CAMERA_ACCESS_TOKEN);

  if (!entityId.startsWith('camera.') || !speakerVolumeEntityId.startsWith('number.')) {
    throw new Error('Kids Room camera configuration must use a camera entity and speaker-volume number entity.');
  }

  if (requiresAccessToken && !accessToken) {
    throw new Error('LEVY_HOME_CAMERA_ACCESS_TOKEN is required when HOME_ASSISTANT_MODE=live.');
  }

  return {
    id: 'kids_room',
    displayName: 'Kids Room',
    entityId,
    speakerVolumeEntityId,
    ...(accessToken ? { accessToken } : {}),
  };
}

type ConfigLogger = Pick<Console, 'info' | 'warn'>;

export function logApnsPrivateKeyStatus(config: AppConfig, logger: ConfigLogger): void {
  const privateKeySource = config.apns.privateKeySource ?? (config.apns.privateKey ? 'inline' : 'none');

  if (privateKeySource === 'path') {
    if (config.apns.privateKey) {
      logger.info('APNs private key file loaded.', {
        envVar: 'APNS_PRIVATE_KEY_PATH',
        filePath: config.apns.privateKeyPath,
        inlineEnvVarIgnored: config.apns.inlinePrivateKeyIgnored || undefined,
      });
      return;
    }

    logger.warn('APNs private key file could not be loaded.', {
      envVar: 'APNS_PRIVATE_KEY_PATH',
      filePath: config.apns.privateKeyPath,
      error: config.apns.privateKeyLoadError,
      inlineEnvVarIgnored: config.apns.inlinePrivateKeyIgnored || undefined,
    });
    return;
  }

  if (privateKeySource === 'inline') {
    logger.info('APNs private key loaded from inline environment variable.', {
      envVar: 'APNS_PRIVATE_KEY',
    });
    return;
  }

  logger.warn('APNs private key is not configured; APNs push delivery is unavailable.', {
    envVar: 'APNS_PRIVATE_KEY_PATH',
  });
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

function readThermostatClimateEntityId(value: string | undefined): string {
  const entityId = readOptionalString(value) ?? 'climate.thermostat';

  if (!entityId.startsWith('climate.')) {
    throw new Error('HOME_ASSISTANT_THERMOSTAT_CLIMATE_ENTITY_ID must be a climate entity ID.');
  }

  return entityId;
}

function readRoomTemperatureSensors(value: string | undefined): CuratedRoomTemperatureSensor[] {
  const rawSensors = readOptionalString(value);

  if (!rawSensors) {
    return defaultRoomTemperatureSensors.map((sensor) => ({ ...sensor }));
  }

  const entries = rawSensors
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [id, name, entityId, ...extraParts] = entry.split(':').map((part) => part.trim());

      if (!isRoomTemperatureSensorID(id) || !name || !entityId || extraParts.length > 0 || !entityId.startsWith('sensor.')) {
        throw new Error(
          `Invalid HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS entry: ${entry}. Expected roomId:Display name:sensor.entity_id.`,
        );
      }

      return { id, name, entityId };
    });

  const byID = new Map(entries.map((entry) => [entry.id, entry]));

  if (byID.size !== defaultRoomTemperatureSensors.length || entries.length !== defaultRoomTemperatureSensors.length) {
    throw new Error('HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS must configure each of the five Levy Home room IDs exactly once.');
  }

  return defaultRoomTemperatureSensors.map((defaultSensor) => {
    const configuredSensor = byID.get(defaultSensor.id);

    if (!configuredSensor) {
      throw new Error('HOME_ASSISTANT_ROOM_TEMPERATURE_SENSORS must configure each of the five Levy Home room IDs exactly once.');
    }

    return configuredSensor;
  });
}

function isRoomTemperatureSensorID(value: string | undefined): value is RoomTemperatureSensorID {
  return defaultRoomTemperatureSensors.some((sensor) => sensor.id === value);
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
