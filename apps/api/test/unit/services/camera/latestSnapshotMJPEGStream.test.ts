import assert from 'node:assert/strict';
import test from 'node:test';

import { createLatestSnapshotMJPEGResponse } from '../../../../src/services/camera/latestSnapshotMJPEGStream.js';

test('latest snapshot MJPEG stream fetches only when the consumer requests the next frame', async () => {
  let latestSnapshot = new Uint8Array([0xff, 0xd8, 0x01, 0xff, 0xd9]);
  let fetchCount = 0;
  const response = createLatestSnapshotMJPEGResponse(async () => {
    fetchCount += 1;
    return { bytes: latestSnapshot, contentType: 'image/jpeg' };
  }, {
    frameIntervalMs: 0,
    sleep: async () => undefined,
  });
  const reader = response.body!.getReader();

  assert.equal(fetchCount, 0);
  const first = await reader.read();
  assert.equal(fetchCount, 1);
  assert.equal(Buffer.from(first.value!).includes(Buffer.from([0xff, 0xd8, 0x01, 0xff, 0xd9])), true);

  latestSnapshot = new Uint8Array([0xff, 0xd8, 0x02, 0xff, 0xd9]);
  const second = await reader.read();
  assert.equal(fetchCount, 2);
  assert.equal(Buffer.from(second.value!).includes(Buffer.from([0xff, 0xd8, 0x02, 0xff, 0xd9])), true);

  await reader.cancel();
});

test('latest snapshot MJPEG stream exposes a valid multipart content type', () => {
  const response = createLatestSnapshotMJPEGResponse(async () => ({
    bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]),
    contentType: 'image/jpeg',
  }));

  assert.equal(
    response.headers.get('content-type'),
    'multipart/x-mixed-replace; boundary=levy-home-frame',
  );
  void response.body?.cancel();
});
