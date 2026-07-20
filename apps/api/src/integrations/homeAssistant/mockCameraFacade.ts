import type { AppConfig } from '../../config.js';
import type { CameraStatus } from '../../contracts.js';

export class MockCameraFacade {
  private isStreaming = false;
  private speakerVolume = 10;

  constructor(private readonly config: AppConfig) {}

  async getStatus(): Promise<CameraStatus> {
    return {
      id: 'kids_room',
      displayName: this.config.homeAssistant.camera.displayName,
      isAvailable: true,
      isStreaming: this.isStreaming,
      speakerVolume: this.speakerVolume,
      lastUpdatedAt: new Date().toISOString(),
    };
  }

  async startStream(): Promise<void> {
    this.isStreaming = true;
  }

  async stopStream(): Promise<void> {
    this.isStreaming = false;
  }

  async openStream(): Promise<Response> {
    return new Response('mock-mjpeg-stream', {
      headers: { 'Content-Type': 'multipart/x-mixed-replace; boundary=mock' },
    });
  }

  async setSpeakerVolume(value: number): Promise<CameraStatus> {
    this.speakerVolume = value;
    return this.getStatus();
  }
}
