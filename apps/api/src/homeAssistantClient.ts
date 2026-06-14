import type { AppConfig, CuratedLightEntity, CuratedLightGroup } from './config.js';
import type { GarageStatus, GarageState, LightGroupStatus, LightState } from './contracts.js';
import { HTTPError } from './httpError.js';

export type HomeAssistantFacade = {
  getGarageStatus(): Promise<GarageStatus>;
  getLightSummaryInputs(): Promise<{
    allLights: LightGroupStatus;
    groups: LightGroupStatus[];
  }>;
  closeGarage(): Promise<void>;
  turnOffAllLights(): Promise<void>;
  turnOffLightGroup(groupId: string): Promise<void>;
};

type HomeAssistantStateResponse = {
  entity_id: string;
  state: string;
  last_updated?: string;
  attributes?: {
    friendly_name?: string;
    entity_id?: string[];
  };
};

export function createHomeAssistantFacade(config: AppConfig): HomeAssistantFacade {
  if (config.homeAssistant.mode === 'live') {
    return new LiveHomeAssistantFacade(config);
  }

  return new MockHomeAssistantFacade(config);
}

class MockHomeAssistantFacade implements HomeAssistantFacade {
  private garageState: GarageState = 'closed';
  private allLightsState: LightState = 'off';
  private readonly groupStates = new Map<string, LightState>();

  constructor(private readonly config: AppConfig) {
    for (const group of config.homeAssistant.lightGroups) {
      this.groupStates.set(group.id, 'off');
    }
  }

  async getGarageStatus(): Promise<GarageStatus> {
    return {
      state: this.garageState,
      displayName: 'Main garage',
      lastUpdatedAt: new Date().toISOString(),
      isStale: false,
    };
  }

  async getLightSummaryInputs(): Promise<{ allLights: LightGroupStatus; groups: LightGroupStatus[] }> {
    const groups = this.config.homeAssistant.lightGroups.map((group) => {
      const state = this.groupStates.get(group.id) ?? 'unknown';
      return {
        id: group.id,
        name: group.name,
        state,
        lightsOnCount: state === 'on' ? 1 : 0,
        totalLightCount: 1,
      };
    });

    return {
      allLights: {
        id: 'all_lights',
        name: 'All lights',
        state: this.allLightsState,
        lightsOnCount: this.allLightsState === 'on' ? this.config.homeAssistant.mockTotalLightCount : 0,
        totalLightCount: this.config.homeAssistant.mockTotalLightCount,
      },
      groups,
    };
  }

  async closeGarage(): Promise<void> {
    this.garageState = 'closed';
  }

  async turnOffAllLights(): Promise<void> {
    this.allLightsState = 'off';

    for (const group of this.config.homeAssistant.lightGroups) {
      this.groupStates.set(group.id, 'off');
    }
  }

  async turnOffLightGroup(groupId: string): Promise<void> {
    if (!this.config.homeAssistant.lightGroups.some((group) => group.id === groupId)) {
      throw new HTTPError(404, `Unknown light group: ${groupId}`, 'unknown_light_group');
    }

    this.groupStates.set(groupId, 'off');
  }
}

class LiveHomeAssistantFacade implements HomeAssistantFacade {
  private readonly baseURL: URL;
  private readonly token: string;

  constructor(private readonly config: AppConfig) {
    if (!config.homeAssistant.baseURL || !config.homeAssistant.token) {
      throw new HTTPError(
        503,
        'Home Assistant live mode requires HOME_ASSISTANT_BASE_URL and HOME_ASSISTANT_TOKEN.',
        'home_assistant_not_configured',
      );
    }

    this.baseURL = new URL(config.homeAssistant.baseURL);
    this.token = config.homeAssistant.token;
  }

  async getGarageStatus(): Promise<GarageStatus> {
    const state = await this.fetchEntityState(this.config.homeAssistant.garageCoverEntityId);

    return {
      state: mapGarageState(state.state),
      displayName: state.attributes?.friendly_name ?? 'Main garage',
      lastUpdatedAt: state.last_updated,
      isStale: false,
    };
  }

  async getLightSummaryInputs(): Promise<{ allLights: LightGroupStatus; groups: LightGroupStatus[] }> {
    if (this.config.homeAssistant.lightEntities.length > 0) {
      const groups = await Promise.all(
        this.config.homeAssistant.lightEntities.map((entity) => this.fetchSingleLightState(entity)),
      );

      return {
        allLights: summarizeLightEntities(groups),
        groups,
      };
    }

    const [allLights, groups] = await Promise.all([
      this.fetchLightGroupState({
        id: 'all_lights',
        name: 'All lights',
        entityId: this.config.homeAssistant.allLightsEntityId,
      }),
      Promise.all(this.config.homeAssistant.lightGroups.map((group) => this.fetchLightGroupState(group))),
    ]);

    return { allLights, groups };
  }

  async closeGarage(): Promise<void> {
    await this.callService('cover', 'close_cover', {
      entity_id: this.config.homeAssistant.garageCoverEntityId,
    });
  }

  async turnOffAllLights(): Promise<void> {
    if (this.config.homeAssistant.lightEntities.length > 0) {
      await this.callService('light', 'turn_off', {
        entity_id: this.config.homeAssistant.lightEntities.map((entity) => entity.entityId),
      });
      return;
    }

    await this.callService('light', 'turn_off', {
      entity_id: this.config.homeAssistant.allLightsEntityId,
    });
  }

  async turnOffLightGroup(groupId: string): Promise<void> {
    const entity = this.config.homeAssistant.lightEntities.find((candidate) => candidate.id === groupId);

    if (entity) {
      await this.callService('light', 'turn_off', {
        entity_id: entity.entityId,
      });
      return;
    }

    const group = this.config.homeAssistant.lightGroups.find((candidate) => candidate.id === groupId);

    if (!group) {
      throw new HTTPError(404, `Unknown light group: ${groupId}`, 'unknown_light_group');
    }

    await this.callService('light', 'turn_off', {
      entity_id: group.entityId,
    });
  }

  private async fetchSingleLightState(entity: CuratedLightEntity): Promise<LightGroupStatus> {
    const state = await this.fetchEntityState(entity.entityId);

    return {
      id: entity.id,
      name: entity.name,
      state: mapLightState(state.state),
      lightsOnCount: state.state === 'on' ? 1 : 0,
      totalLightCount: 1,
    };
  }

  private async fetchLightGroupState(group: CuratedLightGroup): Promise<LightGroupStatus> {
    const state = await this.fetchEntityState(group.entityId);
    const totalLightCount = Array.isArray(state.attributes?.entity_id) ? state.attributes.entity_id.length : undefined;

    return {
      id: group.id,
      name: group.name,
      state: mapLightState(state.state),
      lightsOnCount: state.state === 'on' && totalLightCount ? totalLightCount : state.state === 'on' ? 1 : 0,
      totalLightCount,
    };
  }

  private async fetchEntityState(entityId: string): Promise<HomeAssistantStateResponse> {
    return this.request<HomeAssistantStateResponse>(`/api/states/${encodeURIComponent(entityId)}`);
  }

  private async callService(domain: 'cover' | 'light', service: string, body: { entity_id: string | string[] }): Promise<void> {
    await this.request<unknown>(`/api/services/${domain}/${service}`, {
      method: 'POST',
      body: JSON.stringify(body),
      headers: {
        'Content-Type': 'application/json',
      },
    });
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const url = new URL(path, this.baseURL);
    const response = await fetch(url, {
      ...init,
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: 'application/json',
        ...init.headers,
      },
    });

    if (!response.ok) {
      throw new HTTPError(
        502,
        `Home Assistant request failed with status ${response.status}.`,
        'home_assistant_request_failed',
      );
    }

    if (response.status === 204) {
      return undefined as T;
    }

    return (await response.json()) as T;
  }
}

function summarizeLightEntities(groups: LightGroupStatus[]): LightGroupStatus {
  const lightsOnCount = groups.filter((group) => group.state === 'on').length;
  const totalLightCount = groups.length;

  return {
    id: 'all_lights',
    name: 'All lights',
    state: mapLightCollectionState(groups.map((group) => group.state)),
    lightsOnCount,
    totalLightCount,
  };
}

function mapLightCollectionState(states: LightState[]): LightState {
  if (states.length === 0) {
    return 'unknown';
  }

  if (states.every((state) => state === 'off')) {
    return 'off';
  }

  if (states.every((state) => state === 'on')) {
    return 'on';
  }

  if (states.some((state) => state === 'on')) {
    return 'partially_on';
  }

  return 'unknown';
}

function mapGarageState(state: string): GarageState {
  switch (state) {
  case 'open':
  case 'closed':
  case 'opening':
  case 'closing':
    return state;
  default:
    return 'unknown';
  }
}

function mapLightState(state: string): LightState {
  switch (state) {
  case 'off':
    return 'off';
  case 'on':
    return 'on';
  case 'unavailable':
  case 'unknown':
    return 'unknown';
  default:
    return 'unknown';
  }
}
