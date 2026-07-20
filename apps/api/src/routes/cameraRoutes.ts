import crypto from 'node:crypto';

import { Router, type RequestHandler } from 'express';

import type { CameraService } from '../services/camera/cameraService.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { HTTPError } from '../http/errors.js';

export function createCameraRoutes(cameraService: CameraService, accessToken?: string): Router {
  const router = Router();

  router.use('/api/camera', requireCameraAccessToken(accessToken));

  router.get('/api/camera/kids-room', asyncHandler(async (_req, res) => {
    res.json({ ok: true, camera: await cameraService.getStatus() });
  }));

  router.post('/api/camera/kids-room/sessions', asyncHandler(async (_req, res) => {
    res.status(201).json({ ok: true, session: await cameraService.startSession() });
  }));

  router.delete('/api/camera/kids-room/sessions/:sessionId', asyncHandler(async (req, res) => {
    await cameraService.stopSession(sessionIdFrom(req.params.sessionId));
    res.status(204).end();
  }));

  router.get('/api/camera/kids-room/sessions/:sessionId/stream', asyncHandler(async (req, res) => {
    const sessionId = sessionIdFrom(req.params.sessionId);
    const upstream = await cameraService.openStream(sessionId);
    const contentType = upstream.headers.get('content-type');

    if (!upstream.body || !contentType) {
      throw new HTTPError(502, 'Camera stream is unavailable.', 'camera_stream_unavailable');
    }

    res.status(upstream.status);
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'no-store, private');
    res.on('close', () => {
      void cameraService.stopSession(sessionId).catch(() => undefined);
    });

    for await (const chunk of upstream.body) {
      if (!res.write(chunk)) {
        await new Promise<void>((resolve) => res.once('drain', resolve));
      }
    }

    res.end();
  }));

  router.put('/api/camera/kids-room/speaker-volume', asyncHandler(async (req, res) => {
    const value = typeof req.body?.value === 'number' ? req.body.value : Number.NaN;
    res.json({ ok: true, camera: await cameraService.setSpeakerVolume(value) });
  }));

  return router;
}

function requireCameraAccessToken(expectedToken: string | undefined): RequestHandler {
  return (req, res, next) => {
    if (!expectedToken || hasBearerToken(req.header('Authorization'), expectedToken)) {
      next();
      return;
    }

    res.status(401).json({
      error: 'Unauthorized camera request.',
      code: 'unauthorized_camera_request',
    });
  };
}

function hasBearerToken(authorization: string | undefined, expectedToken: string): boolean {
  const suppliedToken = authorization?.match(/^Bearer (.+)$/i)?.[1];

  if (!suppliedToken) {
    return false;
  }

  const expected = Buffer.from(expectedToken);
  const supplied = Buffer.from(suppliedToken);
  return expected.length === supplied.length && crypto.timingSafeEqual(expected, supplied);
}

function sessionIdFrom(value: string | string[] | undefined): string {
  if (typeof value !== 'string') {
    throw new HTTPError(404, 'Camera session was not found.', 'camera_session_not_found');
  }

  return value;
}
