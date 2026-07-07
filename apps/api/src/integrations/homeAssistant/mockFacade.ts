import type { AppConfig } from '../../config.js';
import type {
  GarageStatus,
  GarageState,
  HomeAssistantEntityDiscoveryCandidate,
  LightGroupStatus,
  LightState,
  PersonPresenceStatus,
} from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import {
  configuredPresenceTrackers,
  normalizePhoneDiscoveryTerms,
  toPhoneDiscoveryCandidate,
  type HomeAssistantStateResponse,
} from './entityDiscovery.js';
import type { HomeAssistantFacade } from './facade.js';

export class MockHomeAssistantFacade implements HomeAssistantFacade {
  private garageState: GarageState = 'closed';
  private allLightsState: LightState = 'off';
  private readonly groupStates = new Map<string, LightState>();

  constructor(private readonly config: AppConfig) {
    for (const group of this.configuredLightTargets()) {
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
    const groups = this.configuredLightTargets().map((group) => {
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

  async discoverPhoneEntities(keywords?: string[]): Promise<HomeAssistantEntityDiscoveryCandidate[]> {
    const terms = normalizePhoneDiscoveryTerms(keywords);
    const mockStates: HomeAssistantStateResponse[] = [
      {
        entity_id: 'sensor.josh_iphone_battery_level',
        state: '82',
        last_changed: new Date().toISOString(),
        last_updated: new Date().toISOString(),
        attributes: { friendly_name: "Joshs iPhone Battery Level" },
      },
      {
        entity_id: 'device_tracker.mallorys_iphone',
        state: 'home',
        last_changed: new Date().toISOString(),
        last_updated: new Date().toISOString(),
        attributes: { friendly_name: "Mallorys iPhone" },
      },
    ];

    return mockStates
      .map((state) => toPhoneDiscoveryCandidate(state, terms))
      .filter((candidate): candidate is HomeAssistantEntityDiscoveryCandidate => candidate !== null);
  }

  async getPresenceStatuses(): Promise<PersonPresenceStatus[]> {
    return configuredPresenceTrackers(this.config).map((tracker, index) => ({
      person: tracker.person,
      state: index === 0 ? 'away' : 'home',
      entityId: tracker.entityId,
      ...(tracker.deviceName ? { deviceName: tracker.deviceName } : {}),
      lastUpdatedAt: new Date().toISOString(),
      isStale: false,
    }));
  }

  async openGarage(): Promise<void> {
    this.garageState = 'open';
  }

  async closeGarage(): Promise<void> {
    this.garageState = 'closed';
  }

  async turnOffAllLights(): Promise<void> {
    this.allLightsState = 'off';

    for (const group of this.configuredLightTargets()) {
      this.groupStates.set(group.id, 'off');
    }
  }

  async turnOnLightGroup(groupId: string): Promise<void> {
    if (!this.hasLightTarget(groupId)) {
      throw new HTTPError(404, `Unknown light group: ${groupId}`, 'unknown_light_group');
    }

    this.groupStates.set(groupId, 'on');
  }

  async turnOffLightGroup(groupId: string): Promise<void> {
    if (!this.hasLightTarget(groupId)) {
      throw new HTTPError(404, `Unknown light group: ${groupId}`, 'unknown_light_group');
    }

    this.groupStates.set(groupId, 'off');
  }

  private configuredLightTargets(): Array<{ id: string; name: string }> {
    return this.config.homeAssistant.lightEntities.length > 0
      ? this.config.homeAssistant.lightEntities
      : this.config.homeAssistant.lightGroups;
  }

  private hasLightTarget(groupId: string): boolean {
    return this.configuredLightTargets().some((group) => group.id === groupId);
  }
}
