import type { AppConfig } from '../../config.js';
import type { CameraPanTiltDirection, CameraStatus } from '../../contracts.js';
import { LiveCameraFacade } from './liveCameraFacade.js';
import { MockCameraFacade } from './mockCameraFacade.js';

export type CameraFacade = {
  getStatus(): Promise<CameraStatus>;
  startStream(): Promise<void>;
  stopStream(): Promise<void>;
  openStream(): Promise<Response>;
  move(direction: CameraPanTiltDirection): Promise<void>;
  setSpeakerVolume(value: number): Promise<CameraStatus>;
};

export function createCameraFacade(config: AppConfig): CameraFacade {
  return config.homeAssistant.mode === 'live'
    ? new LiveCameraFacade(config)
    : new MockCameraFacade(config);
}
