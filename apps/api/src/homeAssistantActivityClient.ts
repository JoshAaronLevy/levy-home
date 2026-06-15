import type { AppConfig, TrackedPhoneEntity, TrackedPhoneEntityPattern } from './config.js';

export type HomeAssistantStateChangedEvent = {
  id?: string;
  entityId: string;
  person: string;
  deviceName?: string;
  oldState?: string;
  newState?: string;
  occurredAt?: string;
  friendlyName?: string;
  ingestionSource?: 'websocket' | 'history';
  isInitialBackfillState?: boolean;
  rawEvent: HomeAssistantWebSocketEvent;
};

export type HomeAssistantActivityListener = {
  start(): void;
  stop(): void;
};

type HomeAssistantActivityListenerOptions = {
  WebSocketImpl?: HomeAssistantWebSocketConstructor;
  onStateChanged?: (event: HomeAssistantStateChangedEvent) => void;
  logger?: Pick<Console, 'info' | 'warn' | 'error'>;
  reconnectDelaysMs?: number[];
  setTimeoutFn?: typeof setTimeout;
  clearTimeoutFn?: typeof clearTimeout;
};

type HomeAssistantWebSocketConstructor = new (url: string) => HomeAssistantWebSocket;

type HomeAssistantWebSocket = {
  readyState?: number;
  addEventListener(type: 'open', listener: () => void): void;
  addEventListener(type: 'message', listener: (event: { data: unknown }) => void): void;
  addEventListener(type: 'close', listener: () => void): void;
  addEventListener(type: 'error', listener: (event: unknown) => void): void;
  close(): void;
  send(data: string): void;
};

type HomeAssistantWebSocketMessage =
  | { type: 'auth_required'; ha_version?: string }
  | { type: 'auth_ok'; ha_version?: string }
  | { type: 'auth_invalid'; message?: string }
  | { type: 'result'; id?: number; success?: boolean; error?: { code?: string; message?: string } }
  | { type: 'event'; id?: number; event?: HomeAssistantWebSocketEvent }
  | { type: string; [key: string]: unknown };

export type HomeAssistantWebSocketEvent = {
  event_type?: string;
  time_fired?: string;
  context?: HomeAssistantContext;
  data?: {
    entity_id?: string;
    old_state?: HomeAssistantEntityState | null;
    new_state?: HomeAssistantEntityState | null;
  };
};

export type HomeAssistantEntityState = {
  entity_id?: string;
  state?: string;
  last_changed?: string;
  last_updated?: string;
  context?: HomeAssistantContext;
  attributes?: {
    friendly_name?: string;
    [key: string]: unknown;
  };
};

export type HomeAssistantContext = {
  id?: string;
  parent_id?: string | null;
  user_id?: string | null;
};

export type ActivityMatch = {
  person: string;
  deviceName?: string;
};

const DEFAULT_RECONNECT_DELAYS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
const SUBSCRIBE_STATE_CHANGED_ID = 1;

export function createHomeAssistantActivityListener(
  config: AppConfig,
  options: HomeAssistantActivityListenerOptions = {},
): HomeAssistantActivityListener | undefined {
  if (!shouldStartHomeAssistantActivityListener(config)) {
    return undefined;
  }

  const webSocketURL = resolveHomeAssistantWebSocketURL(config);
  if (!webSocketURL || !config.homeAssistant.token) {
    options.logger?.warn('Home Assistant activity listener is enabled but live WebSocket credentials are incomplete.');
    return undefined;
  }

  if (
    config.homeAssistant.activity.trackedPhoneEntities.length === 0 &&
    config.homeAssistant.activity.trackedPhoneEntityPatterns.length === 0
  ) {
    options.logger?.warn('Home Assistant activity listener is enabled but no tracked phone entities are configured.');
    return undefined;
  }

  return new DefaultHomeAssistantActivityListener(config, webSocketURL, options);
}

export function shouldStartHomeAssistantActivityListener(config: AppConfig): boolean {
  return config.homeAssistant.mode === 'live' && config.homeAssistant.activity.isEnabled;
}

export function resolveHomeAssistantWebSocketURL(config: AppConfig): string | undefined {
  if (config.homeAssistant.activity.webSocketURL) {
    return config.homeAssistant.activity.webSocketURL;
  }

  if (!config.homeAssistant.baseURL) {
    return undefined;
  }

  const url = new URL('/api/websocket', config.homeAssistant.baseURL);

  if (url.protocol === 'https:') {
    url.protocol = 'wss:';
  } else if (url.protocol === 'http:') {
    url.protocol = 'ws:';
  }

  return url.toString();
}

class DefaultHomeAssistantActivityListener implements HomeAssistantActivityListener {
  private socket: HomeAssistantWebSocket | undefined;
  private isStopped = true;
  private reconnectAttempt = 0;
  private reconnectTimer: ReturnType<typeof setTimeout> | undefined;

  private readonly WebSocketImpl: HomeAssistantWebSocketConstructor;
  private readonly logger: Pick<Console, 'info' | 'warn' | 'error'>;
  private readonly reconnectDelaysMs: number[];
  private readonly setTimeoutFn: typeof setTimeout;
  private readonly clearTimeoutFn: typeof clearTimeout;
  private readonly onStateChanged: (event: HomeAssistantStateChangedEvent) => void;

  constructor(
    private readonly config: AppConfig,
    private readonly webSocketURL: string,
    options: HomeAssistantActivityListenerOptions,
  ) {
    const WebSocketImpl = options.WebSocketImpl ?? defaultWebSocketConstructor();
    if (!WebSocketImpl) {
      throw new Error('A WebSocket implementation is required for Home Assistant activity ingestion.');
    }

    this.WebSocketImpl = WebSocketImpl;
    this.logger = options.logger ?? console;
    this.reconnectDelaysMs = options.reconnectDelaysMs ?? DEFAULT_RECONNECT_DELAYS_MS;
    this.setTimeoutFn = options.setTimeoutFn ?? setTimeout;
    this.clearTimeoutFn = options.clearTimeoutFn ?? clearTimeout;
    this.onStateChanged = options.onStateChanged ?? defaultStateChangedLogger(this.logger);
  }

  start(): void {
    if (!this.isStopped) {
      return;
    }

    this.isStopped = false;
    this.connect();
  }

  stop(): void {
    this.isStopped = true;

    if (this.reconnectTimer) {
      this.clearTimeoutFn(this.reconnectTimer);
      this.reconnectTimer = undefined;
    }

    if (this.socket) {
      this.socket.close();
      this.socket = undefined;
    }
  }

  private connect(): void {
    if (this.isStopped) {
      return;
    }

    try {
      const socket = new this.WebSocketImpl(this.webSocketURL);
      this.socket = socket;

      socket.addEventListener('open', () => {
        this.logger.info('Home Assistant activity listener WebSocket opened.');
      });
      socket.addEventListener('message', (event) => {
        this.handleMessage(event.data);
      });
      socket.addEventListener('close', () => {
        this.socket = undefined;
        this.scheduleReconnect();
      });
      socket.addEventListener('error', () => {
        this.logger.warn('Home Assistant activity listener WebSocket error.');
      });
    } catch (error) {
      this.logger.warn(`Home Assistant activity listener failed to create WebSocket: ${safeErrorMessage(error)}`);
      this.scheduleReconnect();
    }
  }

  private handleMessage(data: unknown): void {
    const message = parseHomeAssistantMessage(data);
    if (!message) {
      this.logger.warn('Home Assistant activity listener received an invalid WebSocket message.');
      return;
    }

    switch (message.type) {
    case 'auth_required':
      this.send({
        type: 'auth',
        access_token: this.config.homeAssistant.token,
      });
      return;
    case 'auth_ok':
      this.reconnectAttempt = 0;
      this.logger.info('Home Assistant activity listener authenticated.');
      this.send({
        id: SUBSCRIBE_STATE_CHANGED_ID,
        type: 'subscribe_events',
        event_type: 'state_changed',
      });
      return;
    case 'auth_invalid':
      this.logger.error('Home Assistant activity listener authentication failed.');
      this.stop();
      return;
    case 'result':
      if (message.id === SUBSCRIBE_STATE_CHANGED_ID) {
        if (message.success) {
          this.logger.info('Home Assistant activity listener subscribed to state_changed events.');
        } else {
          this.logger.warn('Home Assistant activity listener failed to subscribe to state_changed events.');
        }
      }
      return;
    case 'event':
      this.handleEventMessage(isHomeAssistantWebSocketEvent(message.event) ? message.event : undefined);
      return;
    default:
      return;
    }
  }

  private handleEventMessage(event: HomeAssistantWebSocketEvent | undefined): void {
    if (event?.event_type !== 'state_changed') {
      return;
    }

    const entityId = event.data?.entity_id ?? event.data?.new_state?.entity_id ?? event.data?.old_state?.entity_id;
    if (!entityId) {
      return;
    }

    const match = matchTrackedPhoneEntity(
      entityId,
      this.config.homeAssistant.activity.trackedPhoneEntities,
      this.config.homeAssistant.activity.trackedPhoneEntityPatterns,
    );
    if (!match) {
      return;
    }

    this.onStateChanged({
      entityId,
      person: match.person,
      ...(match.deviceName ? { deviceName: match.deviceName } : {}),
      ...(event.data?.old_state?.state ? { oldState: event.data.old_state.state } : {}),
      ...(event.data?.new_state?.state ? { newState: event.data.new_state.state } : {}),
      ...(event.time_fired ? { occurredAt: event.time_fired } : {}),
      ...(event.data?.new_state?.attributes?.friendly_name
        ? { friendlyName: event.data.new_state.attributes.friendly_name }
        : {}),
      ingestionSource: 'websocket',
      rawEvent: event,
    });
  }

  private send(message: Record<string, unknown>): void {
    if (!this.socket) {
      return;
    }

    this.socket.send(JSON.stringify(message));
  }

  private scheduleReconnect(): void {
    if (this.isStopped) {
      return;
    }

    const delay = this.reconnectDelaysMs[Math.min(this.reconnectAttempt, this.reconnectDelaysMs.length - 1)] ?? 30_000;
    this.reconnectAttempt += 1;

    this.logger.warn(`Home Assistant activity listener disconnected; reconnecting in ${delay}ms.`);
    this.reconnectTimer = this.setTimeoutFn(() => {
      this.reconnectTimer = undefined;
      this.connect();
    }, delay);
  }
}

export function matchTrackedPhoneEntity(
  entityId: string,
  entities: TrackedPhoneEntity[],
  patterns: TrackedPhoneEntityPattern[],
): ActivityMatch | undefined {
  const exact = entities.find((entity) => entity.entityId === entityId);
  if (exact) {
    return {
      person: exact.person,
      ...(exact.deviceName ? { deviceName: exact.deviceName } : {}),
    };
  }

  const pattern = patterns.find((candidate) => entityPatternToRegExp(candidate.pattern).test(entityId));
  if (pattern) {
    return {
      person: pattern.person,
      ...(pattern.deviceName ? { deviceName: pattern.deviceName } : {}),
    };
  }

  return undefined;
}

function entityPatternToRegExp(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp(`^${escaped}$`);
}

function parseHomeAssistantMessage(data: unknown): HomeAssistantWebSocketMessage | undefined {
  const text = typeof data === 'string' ? data : data instanceof Buffer ? data.toString('utf8') : undefined;

  if (!text) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(text) as unknown;

    if (isPlainRecord(parsed) && typeof parsed.type === 'string') {
      return parsed as HomeAssistantWebSocketMessage;
    }

    return undefined;
  } catch {
    return undefined;
  }
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isHomeAssistantWebSocketEvent(value: unknown): value is HomeAssistantWebSocketEvent {
  return isPlainRecord(value);
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Unknown WebSocket error.';
}

function defaultStateChangedLogger(
  logger: Pick<Console, 'info'>,
): (event: HomeAssistantStateChangedEvent) => void {
  return (event) => {
    logger.info(`Home Assistant phone activity matched ${event.entityId} for ${event.person}.`);
  };
}

function defaultWebSocketConstructor(): HomeAssistantWebSocketConstructor | undefined {
  return typeof globalThis.WebSocket === 'function'
    ? (globalThis.WebSocket as unknown as HomeAssistantWebSocketConstructor)
    : undefined;
}
