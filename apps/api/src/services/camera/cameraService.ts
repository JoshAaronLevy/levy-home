import crypto from 'node:crypto';

import type { CameraFacade } from '../../integrations/homeAssistant/cameraFacade.js';
import type { CameraPanTiltDirection, CameraSession, CameraStatus } from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';

const SESSION_TTL_MS = 5 * 60 * 1000;

type ActiveCameraSession = CameraSession & { expiresAtMs: number };

export class CameraService {
  private activeSession: ActiveCameraSession | undefined;
  private startInFlight: Promise<CameraSession> | undefined;

  constructor(private readonly facade: CameraFacade) {}

  async getStatus(): Promise<CameraStatus> {
    await this.stopExpiredSession();
    return this.facade.getStatus();
  }

  async startSession(): Promise<CameraSession> {
    await this.stopExpiredSession();

    if (this.activeSession) {
      return toCameraSession(this.activeSession);
    }

    if (!this.startInFlight) {
      this.startInFlight = this.createSession().finally(() => {
        this.startInFlight = undefined;
      });
    }

    return this.startInFlight;
  }

  async stopSession(sessionId: string): Promise<void> {
    if (!this.activeSession || this.activeSession.id !== sessionId) {
      // Closing the brokered MJPEG response can race this explicit cleanup.
      // Stopping an already-ended session is therefore intentionally idempotent.
      return;
    }

    this.activeSession = undefined;
    await this.facade.stopStream();
  }

  async openStream(sessionId: string): Promise<Response> {
    await this.stopExpiredSession();

    if (!this.activeSession || this.activeSession.id !== sessionId) {
      throw new HTTPError(404, 'Camera session was not found or has expired.', 'camera_session_not_found');
    }

    return this.facade.openStream();
  }

  async setSpeakerVolume(value: number): Promise<CameraStatus> {
    if (!Number.isInteger(value) || value < 0 || value > 100) {
      throw new HTTPError(400, 'Camera speaker volume must be an integer from 0 to 100.', 'invalid_camera_speaker_volume');
    }

    return this.facade.setSpeakerVolume(value);
  }

  async move(direction: CameraPanTiltDirection): Promise<void> {
    await this.facade.move(direction);
  }

  private async createSession(): Promise<CameraSession> {
    const status = await this.facade.getStatus();

    if (!status.isAvailable) {
      throw new HTTPError(503, 'Kids Room camera is unavailable.', 'camera_unavailable');
    }

    await this.facade.startStream();
    const expiresAtMs = Date.now() + SESSION_TTL_MS;
    this.activeSession = {
      id: crypto.randomUUID(),
      streamURL: '',
      expiresAt: new Date(expiresAtMs).toISOString(),
      expiresAtMs,
    };
    this.activeSession.streamURL = `/api/camera/kids-room/sessions/${this.activeSession.id}/stream`;

    return toCameraSession(this.activeSession);
  }

  private async stopExpiredSession(): Promise<void> {
    if (!this.activeSession || this.activeSession.expiresAtMs > Date.now()) {
      return;
    }

    this.activeSession = undefined;
    await this.facade.stopStream();
  }
}

function toCameraSession(session: ActiveCameraSession): CameraSession {
  const { expiresAtMs: _expiresAtMs, ...publicSession } = session;
  return publicSession;
}
