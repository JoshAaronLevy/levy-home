import type { AppConfig, CuratedLightEntity, CuratedLightGroup } from '../../config.js';
import type {
  GarageStatus,
  GarageState,
  HomeAssistantEntityDiscoveryCandidate,
  LightGroupStatus,
  LightState,
  PersonPresenceStatus,
  PresenceState,
  ThermostatStatus,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import {
  configuredPresenceTrackers,
  normalizePhoneDiscoveryTerms,
  toPhoneDiscoveryCandidate,
  type HomeAssistantStateResponse,
} from './entityDiscovery.js';
import type { HomeAssistantFacade } from './facade.js';
import { HomeAssistantRestClient } from './restClient.js';

export class LiveHomeAssistantFacade implements HomeAssistantFacade {
  private readonly restClient: HomeAssistantRestClient;

  constructor(private readonly config: AppConfig) {
    if (!config.homeAssistant.baseURL || !config.homeAssistant.token) {
      throw new HTTPError(
        503,
        'Home Assistant live mode requires HOME_ASSISTANT_BASE_URL and HOME_ASSISTANT_TOKEN.',
        'home_assistant_not_configured',
      );
    }

    this.restClient = new HomeAssistantRestClient(config.homeAssistant.baseURL, config.homeAssistant.token);
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

  async getThermostatStatus(): Promise<ThermostatStatus> {
    const state = await this.fetchEntityState(this.config.homeAssistant.thermostatClimateEntityId);

    return {
      currentTemperature: finiteNumberOrNull(state.attributes?.current_temperature),
      targetTemperatureLow: finiteNumberOrNull(state.attributes?.target_temp_low),
      targetTemperatureHigh: finiteNumberOrNull(state.attributes?.target_temp_high),
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

    const groups = await Promise.all(
      this.config.homeAssistant.lightGroups.map((group) => this.fetchLightGroupState(group)),
    );

    if (!this.config.homeAssistant.allLightsEntityId) {
      return {
        allLights: summarizeLightEntities(groups),
        groups,
      };
    }

    const allLights = await this.fetchLightGroupState({
      id: 'all_lights',
      name: 'All lights',
      entityId: this.config.homeAssistant.allLightsEntityId,
    });

    return { allLights, groups };
  }

  async closeGarage(): Promise<void> {
    await this.callService('cover', 'close_cover', {
      entity_id: this.config.homeAssistant.garageCoverEntityId,
    });
  }

  async openGarage(): Promise<void> {
    await this.callService('cover', 'open_cover', {
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

    if (this.config.homeAssistant.allLightsEntityId) {
      await this.callService('light', 'turn_off', {
        entity_id: this.config.homeAssistant.allLightsEntityId,
      });
      return;
    }

    const lightGroupEntityIds = this.config.homeAssistant.lightGroups.map((group) => group.entityId);

    if (lightGroupEntityIds.length > 0) {
      await this.callService('light', 'turn_off', {
        entity_id: lightGroupEntityIds,
      });
      return;
    }

    throw new HTTPError(
      503,
      'No Home Assistant light targets are configured.',
      'home_assistant_lights_not_configured',
    );
  }

  async turnOffLightGroup(groupId: string): Promise<void> {
    const group = this.configuredLightTarget(groupId);
    await this.callService('light', 'turn_off', {
      entity_id: group.entityId,
    });
  }

  async turnOnLightGroup(groupId: string): Promise<void> {
    const group = this.configuredLightTarget(groupId);
    await this.callService('light', 'turn_on', {
      entity_id: group.entityId,
    });
  }

  async discoverPhoneEntities(keywords?: string[]): Promise<HomeAssistantEntityDiscoveryCandidate[]> {
    const terms = normalizePhoneDiscoveryTerms(keywords);
    const states = await this.restClient.request<HomeAssistantStateResponse[]>('/api/states');

    return states
      .map((state) => toPhoneDiscoveryCandidate(state, terms))
      .filter((candidate): candidate is HomeAssistantEntityDiscoveryCandidate => candidate !== null)
      .sort((a, b) => a.entityId.localeCompare(b.entityId));
  }

  async getPresenceStatuses(): Promise<PersonPresenceStatus[]> {
    return Promise.all(
      configuredPresenceTrackers(this.config).map(async (tracker) => {
        try {
          const state = await this.fetchEntityState(tracker.entityId);

          return {
            person: tracker.person,
            state: mapPresenceState(state.state),
            entityId: tracker.entityId,
            ...(tracker.deviceName ? { deviceName: tracker.deviceName } : {}),
            lastUpdatedAt: state.last_updated,
            isStale: false,
          };
        } catch {
          return {
            person: tracker.person,
            state: 'unknown',
            entityId: tracker.entityId,
            ...(tracker.deviceName ? { deviceName: tracker.deviceName } : {}),
            isStale: true,
          };
        }
      }),
    );
  }

  private async fetchSingleLightState(entity: CuratedLightEntity): Promise<LightGroupStatus> {
    const state = await this.fetchEntityState(entity.entityId);
    const totalLightCount = childLightCount(state.attributes?.entity_id);

    return {
      id: entity.id,
      name: entity.name,
      state: mapLightState(state.state),
      lightsOnCount: state.state === 'on' ? totalLightCount : 0,
      totalLightCount,
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
    return this.restClient.request<HomeAssistantStateResponse>(`/api/states/${encodeURIComponent(entityId)}`);
  }

  private configuredLightTarget(groupId: string): CuratedLightEntity | CuratedLightGroup {
    const entity = this.config.homeAssistant.lightEntities.find((candidate) => candidate.id === groupId);

    if (entity) {
      return entity;
    }

    const group = this.config.homeAssistant.lightGroups.find((candidate) => candidate.id === groupId);

    if (!group) {
      throw new HTTPError(404, `Unknown light group: ${groupId}`, 'unknown_light_group');
    }

    return group;
  }

  private async callService(domain: 'cover' | 'light', service: string, body: { entity_id: string | string[] }): Promise<void> {
    await this.restClient.request<unknown>(`/api/services/${domain}/${service}`, {
      method: 'POST',
      body: JSON.stringify(body),
      headers: {
        'Content-Type': 'application/json',
      },
    });
  }
}

function summarizeLightEntities(groups: LightGroupStatus[]): LightGroupStatus {
  const lightsOnCount = groups.reduce((sum, group) => sum + (group.lightsOnCount ?? (group.state === 'on' ? 1 : 0)), 0);
  const totalLightCount = groups.reduce((sum, group) => sum + (group.totalLightCount ?? 1), 0);

  return {
    id: 'all_lights',
    name: 'All lights',
    state: mapLightCollectionState(groups.map((group) => group.state)),
    lightsOnCount,
    totalLightCount,
  };
}

function childLightCount(entityIds: unknown): number {
  if (!Array.isArray(entityIds)) {
    return 1;
  }

  const childCount = entityIds.filter((entityId): entityId is string => typeof entityId === 'string').length;
  return childCount > 0 ? childCount : 1;
}

function finiteNumberOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
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

  if (states.some((state) => state === 'unavailable')) {
    return 'unavailable';
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

function mapPresenceState(state: string): PresenceState {
  switch (state) {
  case 'home':
    return 'home';
  case 'not_home':
    return 'away';
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
    return 'unavailable';
  case 'unknown':
    return 'unknown';
  default:
    return 'unknown';
  }
}
