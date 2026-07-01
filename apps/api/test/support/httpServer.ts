import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import type { Express } from 'express';

export type StartedHttpServer = {
  baseURL: string;
  close: () => Promise<void>;
  server: Server;
};

export async function startHttpServer(app: Express): Promise<StartedHttpServer> {
  const server = await new Promise<Server>((resolve) => {
    const startedServer = app.listen(0, () => {
      resolve(startedServer);
    });
  });
  const address = server.address() as AddressInfo;

  return {
    baseURL: `http://127.0.0.1:${address.port}`,
    close: () => closeHttpServer(server),
    server,
  };
}

export async function closeHttpServer(server: Server): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}
