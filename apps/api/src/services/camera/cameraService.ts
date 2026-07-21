import crypto from 'node:crypto';

import type { CameraFacade } from '../../integrations/homeAssistant/cameraFacade.js';
import type { CameraPanTiltDirection, CameraSession, CameraStatus } from '../../contracts.js';
import { HTTPError } from '../../http/errors.js';
import { logger } from '../../observability/logger.js';

const SESSION_TTL_MS = 5 * 60 * 1000;
const STREAM_RECONCILIATION_ATTEMPTS = 30;
const STREAM_RECONCILIATION_INTERVAL_MS = 1_000;

type ActiveCameraSession = CameraSession & { expiresAtMs: number };
type CameraServiceOptions = {
  reconciliationAttempts?: number;
  reconciliationIntervalMs?: number;
  sleep?: (milliseconds: number) => Promise<void>;
};

export class CameraService {
  private activeSession: ActiveCameraSession | undefined;
  private startInFlight: Promise<CameraSession> | undefined;
  private readonly reconciliationAttempts: number;
  private readonly reconciliationIntervalMs: number;
  private readonly sleep: (milliseconds: number) => Promise<void>;

  constructor(private readonly facade: CameraFacade, options: CameraServiceOptions = {}) {
    this.reconciliationAttempts = options.reconciliationAttempts ?? STREAM_RECONCILIATION_ATTEMPTS;
    this.reconciliationIntervalMs = options.reconciliationIntervalMs ?? STREAM_RECONCILIATION_INTERVAL_MS;
    this.sleep = options.sleep ?? ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
  }

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

    if (!status.isStreaming) {
      try {
        await this.facade.startStream();
      } catch (error) {
        logger.warn('Camera stream start returned an error; reconciling Home Assistant state.', {
          error: error instanceof Error ? error.message : 'Unknown camera stream start error.',
        });

        if (!await this.waitForStreamingState()) {
          throw error;
        }

        logger.info('Camera stream became active after the start error.');
      }
    }

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

  private async waitForStreamingState(): Promise<boolean> {
    for (let attempt = 0; attempt < this.reconciliationAttempts; attempt += 1) {
      await this.sleep(this.reconciliationIntervalMs);

      try {
        if ((await this.facade.getStatus()).isStreaming) {
          return true;
        }
      } catch {
        // Home Assistant can be briefly unavailable while Eufy changes P2P state.
      }
    }

    return false;
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
