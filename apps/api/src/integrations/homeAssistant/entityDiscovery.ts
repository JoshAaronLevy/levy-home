import type { AppConfig } from '../../config.js';
import type { HomeAssistantEntityDiscoveryCandidate } from '../../contracts.js';

export type HomeAssistantStateResponse = {
  entity_id: string;
  state: string;
  last_changed?: string;
  last_updated?: string;
  attributes?: {
    device_class?: string;
    friendly_name?: string;
    entity_id?: string[];
    current_temperature?: number;
    target_temp_low?: number;
    target_temp_high?: number;
  };
};

const DEFAULT_PHONE_DISCOVERY_TERMS = [
  'iphone',
  'josh',
  'mallory',
  'mobile_app',
  'battery_level',
  'battery_state',
  'geocoded_location',
  'connection_type',
  'activity',
  'ssid',
  'bssid',
];

export function configuredPresenceTrackers(config: AppConfig) {
  const trackersByPerson = new Map<string, AppConfig['homeAssistant']['activity']['trackedPhoneEntities'][number]>();

  for (const tracker of config.homeAssistant.activity.trackedPhoneEntities) {
    if (!tracker.entityId.startsWith('device_tracker.')) {
      continue;
    }

    const personKey = tracker.person.trim().toLowerCase();

    if (!trackersByPerson.has(personKey)) {
      trackersByPerson.set(personKey, tracker);
    }
  }

  return Array.from(trackersByPerson.values());
}

export function normalizePhoneDiscoveryTerms(keywords: string[] | undefined): string[] {
  const terms = keywords?.length ? keywords : DEFAULT_PHONE_DISCOVERY_TERMS;
  const normalizedTerms = terms
    .map((term) => normalizeDiscoveryText(term))
    .filter(Boolean);

  return Array.from(new Set(normalizedTerms));
}

export function toPhoneDiscoveryCandidate(
  state: HomeAssistantStateResponse,
  terms: string[],
): HomeAssistantEntityDiscoveryCandidate | null {
  const matchedTerms = matchingPhoneDiscoveryTerms(state, terms);

  if (matchedTerms.length === 0) {
    return null;
  }

  return {
    entityId: state.entity_id,
    domain: state.entity_id.split('.')[0] ?? 'unknown',
    ...(state.attributes?.friendly_name ? { friendlyName: state.attributes.friendly_name } : {}),
    stateSummary: summarizeHomeAssistantState(state.state),
    ...(state.last_changed ? { lastChangedAt: state.last_changed } : {}),
    ...(state.last_updated ? { lastUpdatedAt: state.last_updated } : {}),
    matchedTerms,
  };
}

function matchingPhoneDiscoveryTerms(state: HomeAssistantStateResponse, terms: string[]): string[] {
  const haystack = [
    state.entity_id,
    state.attributes?.friendly_name,
    state.attributes?.device_class,
  ]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => normalizeDiscoveryText(value))
    .join(' ');

  return terms.filter((term) => haystack.includes(term));
}

function normalizeDiscoveryText(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function summarizeHomeAssistantState(value: unknown): string {
  const state = typeof value === 'string' ? value : String(value);

  if (state.length <= 80) {
    return state;
  }

  return `${state.slice(0, 77)}...`;
}
