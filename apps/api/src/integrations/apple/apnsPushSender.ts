import crypto from 'node:crypto';
import http2 from 'node:http2';

import type { AppConfig } from '../../config.js';
import type { APNsEnvironment, APNsSendRequest, APNsSendResult } from '../../contracts.js';

export interface PushSender {
  send(request: APNsSendRequest): Promise<APNsSendResult>;
}

export class APNsConfigurationError extends Error {
  readonly code = 'apns_credentials_not_configured';
}

type APNsCredentials = {
  keyId: string;
  teamId: string;
  bundleId: string;
  privateKey: string;
};

type APNsErrorResponse = {
  reason?: string;
};

const invalidTokenReasons = new Set(['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic']);

export function createAPNsPushSender(config: AppConfig): PushSender {
  return new APNsPushSender(config);
}

class APNsPushSender implements PushSender {
  constructor(private readonly config: AppConfig) {}

  async send(request: APNsSendRequest): Promise<APNsSendResult> {
    const credentials = readCredentials(this.config);
    const environment = request.device.environment ?? this.config.apns.defaultEnvironment;
    const endpoint = endpointForEnvironment(environment);
    const jwt = createProviderToken(credentials);

    return sendAPNsRequest(endpoint, credentials.bundleId, jwt, request);
  }
}

function readCredentials(config: AppConfig): APNsCredentials {
  const missingFields: string[] = [];

  if (!config.apns.keyId) {
    missingFields.push('APNS_KEY_ID');
  }

  if (!config.apns.teamId) {
    missingFields.push('APNS_TEAM_ID');
  }

  if (!config.apns.bundleId) {
    missingFields.push('APNS_BUNDLE_ID');
  }

  const privateKey = config.apns.privateKey;

  if (!privateKey) {
    missingFields.push(privateKeyMissingReason(config));
  }

  if (missingFields.length > 0) {
    throw new APNsConfigurationError(`Missing APNs configuration: ${missingFields.join(', ')}.`);
  }

  return {
    keyId: config.apns.keyId!,
    teamId: config.apns.teamId!,
    bundleId: config.apns.bundleId!,
    privateKey: privateKey!,
  };
}

function privateKeyMissingReason(config: AppConfig): string {
  if (config.apns.privateKeySource === 'path') {
    return config.apns.privateKeyLoadError
      ? `APNS_PRIVATE_KEY_PATH (${config.apns.privateKeyLoadError})`
      : 'APNS_PRIVATE_KEY_PATH';
  }

  return 'APNS_PRIVATE_KEY';
}

function endpointForEnvironment(environment: APNsEnvironment): string {
  return environment === 'production' ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';
}

function createProviderToken(credentials: APNsCredentials): string {
  const header = base64URL(JSON.stringify({ alg: 'ES256', kid: credentials.keyId }));
  const claims = base64URL(JSON.stringify({ iss: credentials.teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${claims}`;
  const signature = crypto.sign('sha256', Buffer.from(signingInput), {
    key: credentials.privateKey,
    dsaEncoding: 'ieee-p1363',
  });

  return `${signingInput}.${base64URL(signature)}`;
}

function sendAPNsRequest(
  endpoint: string,
  topic: string,
  providerToken: string,
  request: APNsSendRequest,
): Promise<APNsSendResult> {
  return new Promise((resolve, reject) => {
    const client = http2.connect(endpoint);
    const payload = JSON.stringify({
      aps: {
        alert: {
          title: request.title,
          body: request.body,
        },
        sound: 'default',
      },
      ...(request.data ? { levyHome: request.data } : {}),
    });
    const stream = client.request({
      ':method': 'POST',
      ':path': `/3/device/${request.device.token}`,
      authorization: `bearer ${providerToken}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    });
    const chunks: Buffer[] = [];
    let statusCode: number | undefined;
    let apnsId: string | undefined;
    let settled = false;

    const settle = (result: APNsSendResult): void => {
      if (settled) {
        return;
      }

      settled = true;
      client.close();
      resolve(result);
    };

    stream.setEncoding('utf8');
    stream.on('response', (headers) => {
      statusCode = Number(headers[':status']);
      const headerAPNsId = headers['apns-id'];
      apnsId = Array.isArray(headerAPNsId) ? headerAPNsId[0] : headerAPNsId;
    });
    stream.on('data', (chunk) => {
      chunks.push(Buffer.from(chunk));
    });
    stream.on('end', () => {
      const reason = parseAPNsReason(Buffer.concat(chunks).toString('utf8'));
      const success = statusCode === 200;

      settle({
        provider: 'apns',
        deviceId: request.device.id,
        success,
        ...(statusCode ? { statusCode } : {}),
        ...(apnsId ? { apnsId } : {}),
        ...(reason ? { reason } : {}),
        isInvalidToken: reason ? invalidTokenReasons.has(reason) : false,
      });
    });
    stream.on('error', (error) => {
      if (settled) {
        return;
      }

      settled = true;
      client.close();
      reject(error);
    });
    client.on('error', (error) => {
      if (settled) {
        return;
      }

      settled = true;
      reject(error);
    });

    stream.end(payload);
  });
}

function parseAPNsReason(rawBody: string): string | undefined {
  if (!rawBody.trim()) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(rawBody) as APNsErrorResponse;
    return typeof parsed.reason === 'string' ? parsed.reason : undefined;
  } catch {
    return rawBody;
  }
}

function base64URL(input: string | Buffer): string {
  return Buffer.from(input).toString('base64url');
}
