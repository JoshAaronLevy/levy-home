import type { AppConfig } from './config.js';
import type {
  HomeOverview,
  LevyHomeEvent,
  LightSummary,
  LightState,
  QuickAction,
  QuickActionId,
  QuickActionResult,
} from './contracts.js';
import type { HomeAssistantFacade } from './integrations/homeAssistant/facade.js';
import { HTTPError } from './http/errors.js';

const importantSeverities = new Set(['warning', 'critical']);

export class HomeService {
  constructor(
    private readonly config: AppConfig,
    private readonly homeAssistant: HomeAssistantFacade,
    private readonly getRecentEvents: () => LevyHomeEvent[],
  ) {}

  async getOverview(): Promise<HomeOverview> {
    const [garageStatus, thermostatStatus, lightSummaryInputs, presence] = await Promise.all([
      this.homeAssistant.getGarageStatus(),
      this.homeAssistant.getThermostatStatus(),
      this.homeAssistant.getLightSummaryInputs(),
      this.homeAssistant.getPresenceStatuses(),
    ]);

    const lightSummary = summarizeLights(lightSummaryInputs.allLights, lightSummaryInputs.groups);

    return {
      garageStatus,
      lightSummary,
      thermostatStatus,
      presence,
      recentImportantEvent: this.findRecentImportantEvent(),
      generatedAt: new Date().toISOString(),
      isPartial: false,
    };
  }

  listQuickActions(): QuickAction[] {
    const lightTargets = this.lightActionTargets();
    const lightGroupTarget =
      lightTargets.length === 1
        ? lightTargets[0]?.name
        : 'Curated light groups';

    return [
      {
        id: 'open_garage',
        title: 'Open Garage',
        subtitle: 'Open the main garage door.',
        isEnabled: true,
        requiresConfirmation: false,
        targetName: 'Main garage',
      },
      {
        id: 'close_garage',
        title: 'Close Garage',
        subtitle: 'Close the main garage door.',
        isEnabled: true,
        requiresConfirmation: true,
        targetName: 'Main garage',
      },
      {
        id: 'turn_off_all_lights',
        title: 'Turn Off All Lights',
        subtitle: 'Turn off the configured all-lights group.',
        isEnabled: true,
        requiresConfirmation: false,
        targetName: 'All lights',
      },
      {
        id: 'turn_on_light_group',
        title: 'Turn On Light Group',
        subtitle: 'Turn on one configured light group.',
        isEnabled: lightTargets.length > 0,
        requiresConfirmation: false,
        targetName: lightGroupTarget,
      },
      {
        id: 'turn_off_light_group',
        title: 'Turn Off Light Group',
        subtitle: 'Turn off one configured light group.',
        isEnabled: lightTargets.length > 0,
        requiresConfirmation: false,
        targetName: lightGroupTarget,
      },
    ];
  }

  async performAction(
    actionId: QuickActionId,
    groupId?: string,
    targetTemperatureLow?: number,
    targetTemperatureHigh?: number,
  ): Promise<QuickActionResult> {
    switch (actionId) {
    case 'open_garage':
      await this.homeAssistant.openGarage();
      return this.result(actionId, 'Garage open requested.');
    case 'close_garage':
      await this.homeAssistant.closeGarage();
      return this.result(actionId, 'Garage close requested.');
    case 'turn_off_all_lights':
      await this.homeAssistant.turnOffAllLights();
      return this.result(actionId, 'All configured lights were turned off.');
    case 'turn_on_light_group':
      if (!groupId) {
        throw new HTTPError(400, 'groupId is required for turn_on_light_group.', 'group_id_required');
      }

      await this.homeAssistant.turnOnLightGroup(groupId);
      return this.result(actionId, 'The selected light group was turned on.');
    case 'turn_off_light_group':
      if (!groupId) {
        throw new HTTPError(400, 'groupId is required for turn_off_light_group.', 'group_id_required');
      }

      await this.homeAssistant.turnOffLightGroup(groupId);
      return this.result(actionId, 'The selected light group was turned off.');
    case 'set_thermostat_temperature':
      if (targetTemperatureLow === undefined || targetTemperatureHigh === undefined) {
        throw new HTTPError(
          400,
          'targetTemperatureLow and targetTemperatureHigh are required for set_thermostat_temperature.',
          'thermostat_temperatures_required',
        );
      }

      if (targetTemperatureHigh - targetTemperatureLow < 7) {
        throw new HTTPError(
          400,
          'Thermostat high temperature must be at least 7° above the low temperature.',
          'thermostat_minimum_delta_required',
        );
      }

      await this.homeAssistant.setThermostatTemperatures(targetTemperatureLow, targetTemperatureHigh);
      return this.result(actionId, 'Thermostat temperatures updated.');
    }
  }

  private async result(actionId: QuickActionId, message: string): Promise<QuickActionResult> {
    return {
      actionId,
      status: 'success',
      message,
      refreshedHomeOverview: await this.getOverview(),
    };
  }

  private findRecentImportantEvent(): LevyHomeEvent | null {
    return (
      this.getRecentEvents().find((event) => importantSeverities.has(event.display.severity) || event.category === 'garage') ??
      null
    );
  }

  private lightActionTargets(): Array<{ id: string; name: string }> {
    return this.config.homeAssistant.lightEntities.length > 0
      ? this.config.homeAssistant.lightEntities
      : this.config.homeAssistant.lightGroups;
  }
}

function summarizeLights(allLights: LightSummary['groups'][number], groups: LightSummary['groups']): LightSummary {
  if (groups.length === 0) {
    return {
      state: allLights.state,
      lightsOnCount: allLights.lightsOnCount,
      totalLightCount: allLights.totalLightCount,
      groups,
    };
  }

  const totalLightCount = sumDefined(groups.map((group) => group.totalLightCount)) ?? allLights.totalLightCount;
  const lightsOnCount = sumDefined(groups.map((group) => group.lightsOnCount)) ?? allLights.lightsOnCount;

  return {
    state: summarizeLightState(groups.map((group) => group.state), allLights.state),
    lightsOnCount,
    totalLightCount,
    groups,
  };
}

function summarizeLightState(groupStates: LightState[], fallback: LightState): LightState {
  if (groupStates.length === 0) {
    return fallback;
  }

  if (groupStates.every((state) => state === 'off')) {
    return 'off';
  }

  if (groupStates.every((state) => state === 'on')) {
    return 'on';
  }

  if (groupStates.some((state) => state === 'on')) {
    return 'partially_on';
  }

  if (groupStates.some((state) => state === 'unavailable')) {
    return 'unavailable';
  }

  return fallback;
}

function sumDefined(values: Array<number | undefined>): number | undefined {
  if (values.some((value) => value === undefined)) {
    return undefined;
  }

  return values.reduce<number>((sum, value) => sum + (value ?? 0), 0);
}
