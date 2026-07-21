import type { AppConfig } from '../../config.js';
import type { CameraPanTiltDirection, CameraStatus } from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import { HomeAssistantRestClient } from './restClient.js';

type HomeAssistantStateResponse = {
  state: string;
  last_updated?: string;
  attributes?: Record<string, unknown>;
};

export class LiveCameraFacade {
  private readonly restClient: HomeAssistantRestClient;

  constructor(private readonly config: AppConfig) {
    if (!config.homeAssistant.baseURL || !config.homeAssistant.token) {
      throw new HTTPError(503, 'Home Assistant live mode requires camera credentials.', 'home_assistant_not_configured');
    }

    this.restClient = new HomeAssistantRestClient(config.homeAssistant.baseURL, config.homeAssistant.token);
  }

  async getStatus(): Promise<CameraStatus> {
    const [camera, speakerVolume] = await Promise.all([
      this.getState(this.config.homeAssistant.camera.entityId),
      this.getState(this.config.homeAssistant.camera.speakerVolumeEntityId),
    ]);
    const volume = Number(speakerVolume.state);

    if (!Number.isFinite(volume)) {
      throw new HTTPError(502, 'Home Assistant returned an invalid camera speaker volume.', 'camera_status_invalid');
    }

    return {
      id: 'kids_room',
      displayName: this.config.homeAssistant.camera.displayName,
      isAvailable: camera.state !== 'unavailable' && camera.state !== 'unknown',
      isStreaming: camera.state === 'streaming',
      speakerVolume: Math.round(volume),
      ...(camera.last_updated ? { lastUpdatedAt: camera.last_updated } : {}),
    };
  }

  async startStream(): Promise<void> {
    await this.callService('eufy_security', 'start_p2p_livestream', {
      entity_id: this.config.homeAssistant.camera.entityId,
    });
  }

  async stopStream(): Promise<void> {
    await this.callService('eufy_security', 'stop_p2p_livestream', {
      entity_id: this.config.homeAssistant.camera.entityId,
    });
  }

  async openStream(): Promise<Response> {
    return this.restClient.requestRaw(
      `/api/camera_proxy_stream/${encodeURIComponent(this.config.homeAssistant.camera.entityId)}`,
    );
  }

  async move(direction: CameraPanTiltDirection): Promise<void> {
    await this.callCameraPTZAction(ptzServiceFor(direction));
  }

  async setSpeakerVolume(value: number): Promise<CameraStatus> {
    await this.callService('number', 'set_value', {
      entity_id: this.config.homeAssistant.camera.speakerVolumeEntityId,
      value,
    });

    return this.getStatus();
  }

  private async getState(entityId: string): Promise<HomeAssistantStateResponse> {
    return this.restClient.request<HomeAssistantStateResponse>(`/api/states/${encodeURIComponent(entityId)}`);
  }

  private async callService(domain: string, service: string, body: Record<string, unknown>): Promise<void> {
    await this.restClient.request<unknown>(`/api/services/${domain}/${service}`, {
      method: 'POST',
      body: JSON.stringify(body),
      headers: { 'Content-Type': 'application/json' },
    });
  }

  private async callCameraPTZAction(service: 'ptz_up' | 'ptz_down' | 'ptz_left' | 'ptz_right'): Promise<void> {
    const webSocketURL = homeAssistantWebSocketURL(this.config.homeAssistant.baseURL);
    const WebSocketImpl = globalThis.WebSocket;

    if (!webSocketURL || !WebSocketImpl) {
      throw new HTTPError(503, 'Home Assistant camera actions are unavailable.', 'home_assistant_action_unavailable');
    }

    await new Promise<void>((resolve, reject) => {
      const socket = new WebSocketImpl(webSocketURL);
      const timeout = setTimeout(() => finish(new HTTPError(
        504,
        'Home Assistant camera action timed out.',
        'home_assistant_action_timeout',
      )), 10_000);
      let settled = false;

      const finish = (error?: Error) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeout);
        socket.close();
        error ? reject(error) : resolve();
      };

      socket.addEventListener('message', (event) => {
        const message = parseWebSocketMessage(event.data);

        if (!message) {
          finish(new HTTPError(502, 'Home Assistant returned an invalid camera action response.', 'home_assistant_action_invalid'));
          return;
        }

        if (message.type === 'auth_required') {
          socket.send(JSON.stringify({ type: 'auth', access_token: this.config.homeAssistant.token }));
          return;
        }

        if (message.type === 'auth_ok') {
          socket.send(JSON.stringify({
            id: 1,
            type: 'call_service',
            domain: 'eufy_security',
            service,
            target: { entity_id: this.config.homeAssistant.camera.entityId },
          }));
          return;
        }

        if (message.type === 'result' && message.id === 1) {
          finish(message.success === false
            ? new HTTPError(502, 'Home Assistant rejected the camera action.', 'home_assistant_action_failed')
            : undefined);
          return;
        }

        if (message.type === 'auth_invalid') {
          finish(new HTTPError(502, 'Home Assistant rejected the camera action credentials.', 'home_assistant_action_auth_failed'));
        }
      });
      socket.addEventListener('error', () => {
        finish(new HTTPError(502, 'Home Assistant camera action connection failed.', 'home_assistant_action_connection_failed'));
      });
      socket.addEventListener('close', () => {
        if (!settled) {
          finish(new HTTPError(502, 'Home Assistant closed the camera action connection.', 'home_assistant_action_connection_closed'));
        }
      });
    });
  }
}

function ptzServiceFor(direction: CameraPanTiltDirection): 'ptz_up' | 'ptz_down' | 'ptz_left' | 'ptz_right' {
  switch (direction) {
  case 'UP': return 'ptz_up';
  case 'DOWN': return 'ptz_down';
  case 'LEFT': return 'ptz_left';
  case 'RIGHT': return 'ptz_right';
  }
}

function homeAssistantWebSocketURL(baseURL: string | undefined): string | undefined {
  if (!baseURL) return undefined;

  const url = new URL('/api/websocket', baseURL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}

function parseWebSocketMessage(data: unknown): {
  type?: string;
  id?: number;
  success?: boolean;
} | undefined {
  const text = typeof data === 'string' ? data : data instanceof Buffer ? data.toString('utf8') : undefined;
  if (!text) return undefined;

  try {
    const parsed = JSON.parse(text) as unknown;
    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)
      ? parsed as { type?: string; id?: number; success?: boolean }
      : undefined;
  } catch {
    return undefined;
  }
}
