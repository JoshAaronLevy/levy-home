import type { AppConfig } from '../../config.js';
import type { CameraStatus } from '../../contracts.js';
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
}
