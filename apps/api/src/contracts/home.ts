import type { LevyHomeEvent } from './activity.js';

export type GarageState = 'open' | 'closed' | 'opening' | 'closing' | 'unknown';
export type LightState = 'off' | 'on' | 'partially_on' | 'unavailable' | 'unknown';
export type PresenceState = 'home' | 'away' | 'unknown';

export type GarageStatus = {
  state: GarageState;
  displayName?: string;
  lastUpdatedAt?: string;
  isStale?: boolean;
};

export type PersonPresenceStatus = {
  person: string;
  state: PresenceState;
  entityId: string;
  deviceName?: string;
  lastUpdatedAt?: string;
  isStale?: boolean;
};

export type LightGroupStatus = {
  id: string;
  name: string;
  state: LightState;
  lightsOnCount?: number;
  totalLightCount?: number;
};

export type LightSummary = {
  state: LightState;
  lightsOnCount?: number;
  totalLightCount?: number;
  groups: LightGroupStatus[];
};

export type ThermostatStatus = {
  currentTemperature: number | null;
  targetTemperatureLow: number | null;
  targetTemperatureHigh: number | null;
  lastUpdatedAt?: string;
  isStale?: boolean;
};

export type HomeOverview = {
  garageStatus: GarageStatus;
  lightSummary: LightSummary;
  thermostatStatus: ThermostatStatus;
  presence: PersonPresenceStatus[];
  recentImportantEvent: LevyHomeEvent | null;
  generatedAt: string;
  isPartial: boolean;
};

export type QuickActionId =
  | 'open_garage'
  | 'close_garage'
  | 'turn_off_all_lights'
  | 'turn_on_light_group'
  | 'turn_off_light_group';

export type QuickAction = {
  id: QuickActionId;
  title: string;
  subtitle?: string;
  isEnabled: boolean;
  requiresConfirmation: boolean;
  targetName?: string;
};

export type QuickActionResult = {
  actionId: QuickActionId;
  status: 'success' | 'failure';
  message: string;
  refreshedHomeOverview: HomeOverview | null;
};
