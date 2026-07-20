import crypto from 'node:crypto';
import type { Request } from 'express';
import type { AppConfig } from '../../config.js';

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const IMAGE_LIFETIME_MS = 10 * 60 * 1000;
type StoredDoorbellImage = { bytes: Buffer; contentType: string; expiresAt: number };

export type DoorbellImageService = {
  capture: (entityId: string, request: Request) => Promise<string | undefined>;
  read: (id: string, expiresAt: string | undefined, signature: string | undefined) => StoredDoorbellImage | undefined;
};

// Fetches the Eufy "latest" image at event time, before it can be overwritten.
// Images are memory-only and usable only for ten minutes through a signed URL.
export function createDoorbellImageService(config: AppConfig): DoorbellImageService {
  const images = new Map<string, StoredDoorbellImage>();
  const signingSecret = config.haWebhookSecret;
  return {
    async capture(entityId, request) {
      if (!signingSecret || !config.homeAssistant.baseURL || !config.homeAssistant.token || !/^image\.[a-z0-9_]+$/i.test(entityId)) return undefined;
      pruneExpired(images);
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 8_000);
      try {
        const response = await fetch(new URL(`/api/image_proxy/${entityId}`, config.homeAssistant.baseURL), {
          headers: { Authorization: `Bearer ${config.homeAssistant.token}` }, signal: controller.signal,
        });
        const contentType = response.headers.get('content-type')?.split(';')[0].toLowerCase() ?? '';
        if (!response.ok || !['image/jpeg', 'image/png', 'image/heic'].includes(contentType)) return undefined;
        const bytes = Buffer.from(await response.arrayBuffer());
        if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) return undefined;
        const id = crypto.randomUUID();
        const expiresAt = Date.now() + IMAGE_LIFETIME_MS;
        images.set(id, { bytes, contentType, expiresAt });
        const expires = Math.floor(expiresAt / 1000).toString();
        const url = new URL(`/api/doorbell-images/${id}`, `${request.protocol}://${request.get('host')}`);
        url.searchParams.set('expires', expires);
        url.searchParams.set('signature', sign(signingSecret, id, expires));
        return url.toString();
      } catch { return undefined; } finally { clearTimeout(timeout); }
    },
    read(id, expires, signature) {
      if (!signingSecret || !expires || !signature || !/^\d+$/.test(expires) || Number(expires) * 1000 < Date.now() || !safeEqual(signature, sign(signingSecret, id, expires))) return undefined;
      const image = images.get(id);
      if (!image || image.expiresAt < Date.now()) { images.delete(id); return undefined; }
      return image;
    },
  };
}

function sign(secret: string, id: string, expires: string): string { return crypto.createHmac('sha256', secret).update(`${id}.${expires}`).digest('base64url'); }
function safeEqual(left: string, right: string): boolean { const a = Buffer.from(left); const b = Buffer.from(right); return a.length === b.length && crypto.timingSafeEqual(a, b); }
function pruneExpired(images: Map<string, StoredDoorbellImage>): void { for (const [id, image] of images) if (image.expiresAt < Date.now()) images.delete(id); }
