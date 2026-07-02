export const LEVY_HOME_EVENT_TYPES = [
  'garage_opened',
  'garage_closed',
  'garage_left_open_10_min',
  'garage_opened_after_hours',
  'garage_still_open_at_10pm',
  'partner_left_home',
  'partner_arrived_home',
  'study_lights_on',
  'doorbell_pressed',
  'doorbell_person_detected',
  'doorbell_motion_detected',
  'phone_state_changed',
] as const;

export type LevyHomeEventType = (typeof LEVY_HOME_EVENT_TYPES)[number];

export type DisplaySeverity = 'info' | 'warning' | 'critical';
export type HomeAssistantEventCategory = 'garage' | 'doorbell' | 'phone' | 'presence' | 'lighting';
export type HomeAssistantEventSeverity = 'normal' | 'high';

export type HomeAssistantEntityDiscoveryCandidate = {
  entityId: string;
  domain: string;
  friendlyName?: string;
  stateSummary: string;
  lastChangedAt?: string;
  lastUpdatedAt?: string;
  matchedTerms: string[];
};

export type EventDisplayMetadata = {
  title: string;
  body: string;
  severity: DisplaySeverity;
};

export type HomeAssistantEventPayload = {
  type: LevyHomeEventType;
  entityId: string;
  category?: HomeAssistantEventCategory;
  severity?: HomeAssistantEventSeverity;
  source?: string;
  occurredAt?: string;
  title?: string;
  message?: string;
  metadata?: Record<string, unknown>;
};

export type EventPushStatus = {
  attempted: boolean;
  skipped: boolean;
  reason?: string;
  ticketCount?: number;
  sentNotificationCount?: number;
  failedNotificationCount?: number;
  invalidTokenCount?: number;
};

export type LevyHomeEvent = HomeAssistantEventPayload & {
  id: string;
  receivedAt: string;
  display: EventDisplayMetadata;
  push?: EventPushStatus;
};

export const EVENT_DISPLAY_METADATA: Record<LevyHomeEventType, EventDisplayMetadata> = {
  garage_opened: {
    title: 'Garage opened',
    body: 'The garage door opened.',
    severity: 'info',
  },
  garage_closed: {
    title: 'Garage closed',
    body: 'The garage door closed.',
    severity: 'info',
  },
  garage_left_open_10_min: {
    title: 'Garage left open',
    body: 'The garage has been open for 10 minutes.',
    severity: 'warning',
  },
  garage_opened_after_hours: {
    title: 'Garage opened after hours',
    body: 'The garage opened between 10 PM and 7 AM.',
    severity: 'warning',
  },
  garage_still_open_at_10pm: {
    title: 'Garage still open',
    body: 'The garage is still open at 10 PM.',
    severity: 'critical',
  },
  partner_left_home: {
    title: 'Partner left home',
    body: 'A household member left home.',
    severity: 'info',
  },
  partner_arrived_home: {
    title: 'Partner arrived home',
    body: 'A household member arrived home.',
    severity: 'info',
  },
  study_lights_on: {
    title: 'Study lights on',
    body: 'Study: Let there be light!',
    severity: 'info',
  },
  doorbell_pressed: {
    title: 'Doorbell pressed',
    body: 'Someone pressed the doorbell.',
    severity: 'info',
  },
  doorbell_person_detected: {
    title: 'Person detected',
    body: 'The doorbell detected a person.',
    severity: 'warning',
  },
  doorbell_motion_detected: {
    title: 'Motion detected',
    body: 'The doorbell detected motion.',
    severity: 'info',
  },
  phone_state_changed: {
    title: 'Phone changed',
    body: 'A tracked phone entity changed state.',
    severity: 'info',
  },
};

const eventTypeSet = new Set<string>(LEVY_HOME_EVENT_TYPES);

export function isLevyHomeEventType(value: unknown): value is LevyHomeEventType {
  return typeof value === 'string' && eventTypeSet.has(value);
}

export function getEventDisplayMetadata(type: LevyHomeEventType): EventDisplayMetadata {
  return EVENT_DISPLAY_METADATA[type];
}

export function buildEventDedupeKey(event: Pick<HomeAssistantEventPayload, 'type' | 'entityId'>): string {
  return `${event.type}:${event.entityId}`;
}
