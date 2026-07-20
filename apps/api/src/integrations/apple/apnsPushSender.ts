import crypto from 'node:crypto';
import http2 from 'node:http2';

import type { AppConfig } from '../../config.js';
import type {
  APNsEnvironment,
  APNsSendRequest,
  APNsSendResult,
  ShoppingLiveActivityPayload,
} from '../../contracts.js';

export interface PushSender {
  send(request: APNsSendRequest): Promise<APNsSendResult>;
}

export type ShoppingLiveActivityPushRequest = {
  registrationId: string;
  token: string;
  environment: APNsEnvironment;
  payload: ShoppingLiveActivityPayload;
  priority: 5 | 10;
  expiration: number;
};

export type ShoppingLiveActivityPushResult = {
  registrationId: string;
  success: boolean;
  statusCode?: number;
  apnsId?: string;
  reason?: string;
  isInvalidToken: boolean;
};

export interface ShoppingLiveActivityPushSender {
  send(request: ShoppingLiveActivityPushRequest): Promise<ShoppingLiveActivityPushResult>;
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

export function createAPNsShoppingLiveActivityPushSender(config: AppConfig): ShoppingLiveActivityPushSender {
  return new APNsShoppingLiveActivityPushSender(config);
}

class APNsPushSender implements PushSender {
  constructor(private readonly config: AppConfig) {}

  async send(request: APNsSendRequest): Promise<APNsSendResult> {
    const credentials = readCredentials(this.config);
    const environment = request.device.environment ?? this.config.apns.defaultEnvironment;
    const endpoint = endpointForEnvironment(environment);
    const jwt = createProviderToken(credentials);

    const result = await sendAPNsPayload(endpoint, jwt, {
      token: request.device.token,
      topic: credentials.bundleId,
      pushType: 'alert',
      priority: 10,
      ...(request.collapseId ? { collapseId: request.collapseId } : {}),
      ...(request.expiration !== undefined ? { expiration: request.expiration } : {}),
      payload: JSON.stringify({
        aps: {
          alert: {
            title: request.title,
            body: request.body,
          },
          sound: 'default',
          ...(request.mutableContent ? { 'mutable-content': 1 } : {}),
        },
        ...(request.data ? { levyHome: request.data } : {}),
      }),
    });

    return {
      provider: 'apns',
      deviceId: request.device.id,
      ...result,
    };
  }
}

class APNsShoppingLiveActivityPushSender implements ShoppingLiveActivityPushSender {
  constructor(private readonly config: AppConfig) {}

  async send(request: ShoppingLiveActivityPushRequest): Promise<ShoppingLiveActivityPushResult> {
    const credentials = readCredentials(this.config);
    const apnsRequest = buildShoppingLiveActivityAPNsRequest(credentials.bundleId, request);
    const result = await sendAPNsPayload(
      apnsRequest.endpoint,
      createProviderToken(credentials),
      {
        token: request.token,
        topic: apnsRequest.topic,
        pushType: 'liveactivity',
        priority: request.priority,
        expiration: request.expiration,
        payload: apnsRequest.payload,
      },
    );

    return {
      registrationId: request.registrationId,
      ...result,
    };
  }
}

export function buildShoppingLiveActivityAPNsRequest(
  bundleId: string,
  request: ShoppingLiveActivityPushRequest,
): {
  endpoint: string;
  path: string;
  topic: string;
  pushType: 'liveactivity';
  priority: 5 | 10;
  expiration: number;
  payload: string;
} {
  return {
    endpoint: endpointForEnvironment(request.environment),
    path: `/3/device/${request.token}`,
    topic: `${bundleId}.push-type.liveactivity`,
    pushType: 'liveactivity',
    priority: request.priority,
    expiration: request.expiration,
    payload: JSON.stringify(request.payload),
  };
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

type APNsPayloadRequest = {
  token: string;
  topic: string;
  pushType: 'alert' | 'liveactivity';
  priority: 5 | 10;
  expiration?: number;
  collapseId?: string;
  payload: string;
};

type APNsPayloadResult = Omit<APNsSendResult, 'provider' | 'deviceId'>;

function sendAPNsPayload(
  endpoint: string,
  providerToken: string,
  request: APNsPayloadRequest,
): Promise<APNsPayloadResult> {
  return new Promise((resolve, reject) => {
    const client = http2.connect(endpoint);
    const stream = client.request({
      ':method': 'POST',
      ':path': `/3/device/${request.token}`,
      authorization: `bearer ${providerToken}`,
      'apns-topic': request.topic,
      'apns-push-type': request.pushType,
      'apns-priority': String(request.priority),
      ...(request.expiration !== undefined ? { 'apns-expiration': String(request.expiration) } : {}),
      ...(request.collapseId ? { 'apns-collapse-id': request.collapseId } : {}),
      'content-type': 'application/json',
    });
    const chunks: Buffer[] = [];
    let statusCode: number | undefined;
    let apnsId: string | undefined;
    let settled = false;

    const settle = (result: APNsPayloadResult): void => {
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

    stream.end(request.payload);
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
