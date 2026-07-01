import assert from 'node:assert/strict';
import type { Express } from 'express';

import { startHttpServer, type StartedHttpServer } from './httpServer.js';

export type RouteTestHarness = {
  baseURL: () => string;
  close: () => Promise<void>;
  getJSON: (path: string) => Promise<any>;
  postJSON: (
    path: string,
    body?: Record<string, unknown>,
    headers?: Record<string, string>,
  ) => Promise<any>;
  putJSON: (
    path: string,
    body: Record<string, unknown>,
    headers?: Record<string, string>,
  ) => Promise<any>;
  restart: (app: Express) => Promise<void>;
  start: (app: Express) => Promise<void>;
  stop: () => Promise<void>;
};

export function createRouteTestHarness(): RouteTestHarness {
  let testServer: StartedHttpServer | undefined;
  let baseURL: string | undefined;

  async function start(app: Express): Promise<void> {
    testServer = await startHttpServer(app);
    baseURL = testServer.baseURL;
  }

  async function stop(): Promise<void> {
    if (!testServer) {
      return;
    }

    await testServer.close();
    testServer = undefined;
    baseURL = undefined;
  }

  function requireBaseURL(): string {
    if (!baseURL) {
      throw new Error('Route test server has not been started.');
    }

    return baseURL;
  }

  return {
    baseURL: requireBaseURL,
    close: stop,
    async getJSON(path) {
      const response = await fetch(`${requireBaseURL()}${path}`);
      assert.equal(response.ok, true);
      return response.json();
    },
    async postJSON(path, body, headers = {}) {
      const response = await fetch(`${requireBaseURL()}${path}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });

      assert.equal(response.ok, true);
      return response.json();
    },
    async putJSON(path, body, headers = {}) {
      const response = await fetch(`${requireBaseURL()}${path}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: JSON.stringify(body),
      });

      assert.equal(response.ok, true);
      return response.json();
    },
    async restart(app) {
      await stop();
      await start(app);
    },
    start,
    stop,
  };
}
