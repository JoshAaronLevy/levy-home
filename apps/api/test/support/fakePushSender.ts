import type { PushSender } from '../../src/integrations/apple/apnsPushSender.js';
import type { APNsSendRequest, APNsSendResult } from '../../src/contracts.js';

export class FakePushSender implements PushSender {
  readonly requests: APNsSendRequest[] = [];

  constructor(private readonly results: Partial<APNsSendResult>[] = []) {}

  async send(request: APNsSendRequest): Promise<APNsSendResult> {
    this.requests.push(request);
    const result = this.results.shift();

    return {
      provider: 'apns',
      deviceId: request.device.id,
      success: true,
      statusCode: 200,
      isInvalidToken: false,
      ...result,
    };
  }
}
