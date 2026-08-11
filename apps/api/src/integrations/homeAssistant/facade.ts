import type { AppConfig } from '../../config.js';
import type {
  GarageStatus,
  HomeAssistantEntityDiscoveryCandidate,
  LightGroupStatus,
  PersonPresenceStatus,
  RoomTemperatureReading,
  ThermostatStatus,
} from '../../contracts.js';
import { LiveHomeAssistantFacade } from './liveFacade.js';
import { MockHomeAssistantFacade } from './mockFacade.js';

export type HomeAssistantFacade = {
  getGarageStatus(): Promise<GarageStatus>;
  getThermostatStatus(): Promise<ThermostatStatus>;
  getRoomTemperatures(): Promise<RoomTemperatureReading[]>;
  getOccupiedMeanTemperature(): Promise<number | null>;
  setThermostatTemperatures(targetTemperatureLow: number, targetTemperatureHigh: number): Promise<void>;
  getLightSummaryInputs(): Promise<{
    allLights: LightGroupStatus;
    groups: LightGroupStatus[];
  }>;
  getPresenceStatuses(): Promise<PersonPresenceStatus[]>;
  discoverPhoneEntities(keywords?: string[]): Promise<HomeAssistantEntityDiscoveryCandidate[]>;
  openGarage(): Promise<void>;
  closeGarage(): Promise<void>;
  turnOffAllLights(): Promise<void>;
  turnOnLightGroup(groupId: string): Promise<void>;
  turnOffLightGroup(groupId: string): Promise<void>;
};

export function createHomeAssistantFacade(config: AppConfig): HomeAssistantFacade {
  if (config.homeAssistant.mode === 'live') {
    return new LiveHomeAssistantFacade(config);
  }

  return new MockHomeAssistantFacade(config);
}
