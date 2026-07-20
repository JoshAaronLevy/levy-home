import { HTTPError } from '../../http/errors.js';

export class HomeAssistantRestClient {
  private readonly baseURL: URL;

  constructor(
    baseURL: string,
    private readonly token: string,
  ) {
    this.baseURL = new URL(baseURL);
  }

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await this.requestRaw(path, init);

    if (response.status === 204) {
      return undefined as T;
    }

    return (await response.json()) as T;
  }

  async requestRaw(path: string, init: RequestInit = {}): Promise<Response> {
    const url = new URL(path, this.baseURL);
    const response = await fetch(url, {
      ...init,
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: 'application/json',
        ...init.headers,
      },
    });

    if (!response.ok) {
      throw new HTTPError(
        502,
        `Home Assistant request failed with status ${response.status}.`,
        'home_assistant_request_failed',
      );
    }

    return response;
  }
}
