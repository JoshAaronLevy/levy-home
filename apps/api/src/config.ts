import type { LightGroupStatus } from './contracts.js';

export type HomeAssistantMode = 'mock' | 'live';

export type CuratedLightGroup = Pick<LightGroupStatus, 'id' | 'name'> & {
  entityId: string;
};

export type AppConfig = {
  port: number;
  haWebhookSecret?: string;
  homeAssistant: {
    mode: HomeAssistantMode;
    baseURL?: string;
    token?: string;
    garageCoverEntityId: string;
    allLightsEntityId: string;
    lightGroups: CuratedLightGroup[];
    mockTotalLightCount: number;
  };
};

export function readConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return {
    port: readNumber(env.PORT, 4000),
    haWebhookSecret: readOptionalString(env.LEVY_HOME_HA_WEBHOOK_SECRET),
    homeAssistant: {
      mode: readHomeAssistantMode(env.HOME_ASSISTANT_MODE),
      baseURL: readOptionalString(env.HOME_ASSISTANT_BASE_URL),
      token: readOptionalString(env.HOME_ASSISTANT_TOKEN),
      garageCoverEntityId: readOptionalString(env.HOME_ASSISTANT_GARAGE_COVER_ENTITY_ID) ?? 'cover.main_garage_door',
      allLightsEntityId: readOptionalString(env.HOME_ASSISTANT_ALL_LIGHTS_ENTITY_ID) ?? 'light.all_lights',
      lightGroups: readLightGroups(env.HOME_ASSISTANT_LIGHT_GROUPS),
      mockTotalLightCount: readNumber(env.MOCK_TOTAL_LIGHT_COUNT, 12),
    },
  };
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

function readOptionalString(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function readLightGroups(value: string | undefined): CuratedLightGroup[] {
  const rawGroups = readOptionalString(value);

  if (!rawGroups) {
    return [
      { id: 'downstairs', name: 'Downstairs lights', entityId: 'light.downstairs_lights' },
      { id: 'bedrooms', name: 'Bedroom lights', entityId: 'light.bedroom_lights' },
    ];
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
