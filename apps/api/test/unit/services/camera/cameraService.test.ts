import assert from 'node:assert/strict';
import test from 'node:test';

import type { CameraStatus } from '../../../../src/contracts.js';
import type { CameraFacade } from '../../../../src/integrations/homeAssistant/cameraFacade.js';
import { CameraService } from '../../../../src/services/camera/cameraService.js';

test('camera session reuses an already-streaming Home Assistant feed', async () => {
  const facade = new CameraFacadeStub([cameraStatus(true)]);
  const service = new CameraService(facade);

  const session = await service.startSession();

  assert.match(session.id, /^[0-9a-f-]{36}$/);
  assert.equal(facade.startStreamCallCount, 0);
});

test('camera session reconciles a delayed stream that becomes active after a start error', async () => {
  const facade = new CameraFacadeStub([
    cameraStatus(false),
    cameraStatus(false),
    cameraStatus(true),
  ]);
  facade.startStreamError = new Error('Home Assistant request failed with status 500.');
  const service = new CameraService(facade, {
    reconciliationAttempts: 2,
    reconciliationIntervalMs: 0,
    sleep: async () => undefined,
  });

  const session = await service.startSession();

  assert.match(session.id, /^[0-9a-f-]{36}$/);
  assert.equal(facade.startStreamCallCount, 1);
  assert.equal(facade.getStatusCallCount, 3);
});

test('camera session preserves the start error when the stream never becomes active', async () => {
  const facade = new CameraFacadeStub([
    cameraStatus(false),
    cameraStatus(false),
    cameraStatus(false),
  ]);
  const startError = new Error('Home Assistant request failed with status 500.');
  facade.startStreamError = startError;
  const service = new CameraService(facade, {
    reconciliationAttempts: 2,
    reconciliationIntervalMs: 0,
    sleep: async () => undefined,
  });

  await assert.rejects(service.startSession(), (error) => error === startError);
  assert.equal(facade.startStreamCallCount, 1);
});

class CameraFacadeStub implements CameraFacade {
  startStreamCallCount = 0;
  getStatusCallCount = 0;
  startStreamError: Error | undefined;
  private readonly statuses: CameraStatus[];

  constructor(statuses: CameraStatus[]) {
    this.statuses = statuses;
  }

  async getStatus(): Promise<CameraStatus> {
    const index = Math.min(this.getStatusCallCount, this.statuses.length - 1);
    this.getStatusCallCount += 1;
    return this.statuses[index]!;
  }

  async startStream(): Promise<void> {
    this.startStreamCallCount += 1;
    if (this.startStreamError) throw this.startStreamError;
  }

  async stopStream(): Promise<void> {}

  async openStream(): Promise<Response> {
    return new Response();
  }

  async move(): Promise<void> {}

  async setSpeakerVolume(): Promise<CameraStatus> {
    return this.statuses.at(-1)!;
  }
}

function cameraStatus(isStreaming: boolean): CameraStatus {
  return {
    id: 'kids_room',
    displayName: 'Kids Room',
    isAvailable: true,
    isStreaming,
    speakerVolume: 10,
  };
}
