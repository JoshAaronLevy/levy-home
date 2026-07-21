import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { createApp } from '../../../src/app.js';
import { createRouteTestHarness } from '../../support/routeTestHarness.js';
import { testConfig } from '../../support/testConfig.js';

const routes = createRouteTestHarness();
const cameraHeaders = { Authorization: 'Bearer test-camera-access-token' };

beforeEach(async () => {
  await routes.start(createApp({ config: testConfig }));
});

afterEach(async () => {
  await routes.close();
});

test('camera routes expose only the curated Kids Room camera and broker its mock MJPEG stream', async () => {
  const initialStatusResponse = await fetch(`${routes.baseURL()}/api/camera/kids-room`, { headers: cameraHeaders });
  assert.equal(initialStatusResponse.status, 200);
  const initialStatus = await initialStatusResponse.json();
  assert.deepEqual(initialStatus.camera, {
    id: 'kids_room',
    displayName: 'Kids Room',
    isAvailable: true,
    isStreaming: false,
    speakerVolume: 10,
    lastUpdatedAt: initialStatus.camera.lastUpdatedAt,
  });

  const created = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions`, {
    method: 'POST',
    headers: cameraHeaders,
  });
  const createdBody = (await created.json()) as {
    ok: boolean;
    session: { id: string; streamURL: string; expiresAt: string };
  };
  assert.equal(created.status, 201);
  assert.equal(createdBody.ok, true);
  assert.match(createdBody.session.id, /^[0-9a-f-]{36}$/);
  assert.equal(createdBody.session.streamURL, `/api/camera/kids-room/sessions/${createdBody.session.id}/stream`);
  assert.ok(Date.parse(createdBody.session.expiresAt) > Date.now());

  const stream = await fetch(`${routes.baseURL()}${createdBody.session.streamURL}`, { headers: cameraHeaders });
  assert.equal(stream.status, 200);
  assert.equal(stream.headers.get('content-type'), 'multipart/x-mixed-replace; boundary=mock');
  assert.equal(await stream.text(), 'mock-mjpeg-stream');
});

test('camera session cleanup is idempotent while stream access still requires the opaque active session ID', async () => {
  const createdResponse = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions`, {
    method: 'POST',
    headers: cameraHeaders,
  });
  const created = (await createdResponse.json()) as { session: { id: string } };
  const sessionId = created.session.id as string;

  const wrongStop = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions/not-a-session`, {
    method: 'DELETE',
    headers: cameraHeaders,
  });
  assert.equal(wrongStop.status, 204);

  const stopped = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions/${sessionId}`, {
    method: 'DELETE',
    headers: cameraHeaders,
  });
  assert.equal(stopped.status, 204);

  const repeatedStop = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions/${sessionId}`, {
    method: 'DELETE',
    headers: cameraHeaders,
  });
  assert.equal(repeatedStop.status, 204);

  const expiredStream = await fetch(`${routes.baseURL()}/api/camera/kids-room/sessions/${sessionId}/stream`, {
    headers: cameraHeaders,
  });
  const expiredStreamBody = (await expiredStream.json()) as { code: string };
  assert.equal(expiredStream.status, 404);
  assert.equal(expiredStreamBody.code, 'camera_session_not_found');
});

test('camera speaker volume accepts only the bounded camera speaker setting', async () => {
  const updated = await routes.putJSON('/api/camera/kids-room/speaker-volume', { value: 42 }, cameraHeaders);
  assert.equal(updated.camera.speakerVolume, 42);

  const invalid = await fetch(`${routes.baseURL()}/api/camera/kids-room/speaker-volume`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', ...cameraHeaders },
    body: JSON.stringify({ value: 101 }),
  });
  const invalidBody = (await invalid.json()) as { code: string };
  assert.equal(invalid.status, 400);
  assert.equal(invalidBody.code, 'invalid_camera_speaker_volume');
});

test('camera PTZ accepts only the approved four directions', async () => {
  const moved = await fetch(`${routes.baseURL()}/api/camera/kids-room/ptz`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...cameraHeaders },
    body: JSON.stringify({ direction: 'UP' }),
  });
  assert.equal(moved.status, 204);

  const invalid = await fetch(`${routes.baseURL()}/api/camera/kids-room/ptz`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...cameraHeaders },
    body: JSON.stringify({ direction: 'ROTATE360' }),
  });
  const invalidBody = (await invalid.json()) as { code: string };
  assert.equal(invalid.status, 400);
  assert.equal(invalidBody.code, 'invalid_camera_direction');
});

test('camera routes require the configured Levy Home camera credential', async () => {
  const response = await fetch(`${routes.baseURL()}/api/camera/kids-room`);
  const body = (await response.json()) as { code: string };

  assert.equal(response.status, 401);
  assert.equal(body.code, 'unauthorized_camera_request');
});
