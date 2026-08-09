import type { QuickActionId } from '../contracts/home.js';
import { HTTPError } from '../http/errors.js';
import { isPlainRecord } from './shared.js';

const quickActionIds = new Set<QuickActionId>([
  'open_garage',
  'close_garage',
  'turn_off_all_lights',
  'turn_on_light_group',
  'turn_off_light_group',
  'set_thermostat_temperature',
]);
const allowedQuickActionBodyKeys = new Set(['actionId', 'groupId', 'targetTemperatureLow', 'targetTemperatureHigh']);
const forbiddenHomeAssistantKeys = new Set([
  'domain',
  'service',
  'serviceData',
  'service_data',
  'entityId',
  'entity_id',
  'target',
]);

export type QuickActionBody = {
  actionId: QuickActionId;
  groupId?: string;
  targetTemperatureLow?: number;
  targetTemperatureHigh?: number;
};

export function validateQuickActionBody(input: unknown): QuickActionBody {
  if (!isPlainRecord(input)) {
    throw new HTTPError(400, 'Expected a JSON object quick-action payload.', 'invalid_action_payload');
  }

  const keys = Object.keys(input);
  const forbiddenKey = keys.find((key) => forbiddenHomeAssistantKeys.has(key));

  if (forbiddenKey) {
    throw new HTTPError(
      400,
      'Arbitrary Home Assistant service/entity payloads are not supported.',
      'arbitrary_home_assistant_payload_rejected',
    );
  }

  const unsupportedKey = keys.find((key) => !allowedQuickActionBodyKeys.has(key));

  if (unsupportedKey) {
    throw new HTTPError(400, `Unsupported quick-action field: ${unsupportedKey}`, 'unsupported_action_field');
  }

  if (!quickActionIds.has(input.actionId as QuickActionId)) {
    throw new HTTPError(400, 'Unsupported quick action.', 'unsupported_action');
  }

  if (input.groupId !== undefined && typeof input.groupId !== 'string') {
    throw new HTTPError(400, 'groupId must be a string when provided.', 'invalid_group_id');
  }

  const groupId = typeof input.groupId === 'string' && input.groupId.trim() ? input.groupId.trim() : undefined;
  const actionId = input.actionId as QuickActionId;
  const targetTemperatureLow = numberOrUndefined(input.targetTemperatureLow);
  const targetTemperatureHigh = numberOrUndefined(input.targetTemperatureHigh);

  if (actionId === 'set_thermostat_temperature') {
    if (targetTemperatureLow === undefined || targetTemperatureHigh === undefined) {
      throw new HTTPError(
        400,
        'targetTemperatureLow and targetTemperatureHigh are required for set_thermostat_temperature.',
        'thermostat_temperatures_required',
      );
    }

    return { actionId, targetTemperatureLow, targetTemperatureHigh };
  }

  if (targetTemperatureLow !== undefined || targetTemperatureHigh !== undefined) {
    throw new HTTPError(400, 'Thermostat temperatures are only supported for set_thermostat_temperature.', 'unsupported_action_field');
  }

  return { actionId, ...(groupId ? { groupId } : {}) };
}

function numberOrUndefined(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new HTTPError(400, 'Thermostat temperatures must be finite numbers when provided.', 'invalid_thermostat_temperature');
  }

  return value;
}
