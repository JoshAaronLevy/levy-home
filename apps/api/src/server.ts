import 'dotenv/config';

import { pathToFileURL } from 'node:url';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from './activityNormalizer.js';
import { createRecentActivityStore } from './activityStore.js';
import { createApp } from './app.js';
import { readConfig } from './config.js';
import { backfillHomeAssistantActivity } from './homeAssistantActivityBackfill.js';
import {
  createHomeAssistantActivityListener,
  type HomeAssistantStateChangedEvent,
} from './homeAssistantActivityClient.js';
import { createShoppingListRealtimeHub } from './shoppingListRealtime.js';

export function startServer(config = readConfig()): void {
  const activityStore = createRecentActivityStore(500);
  const shoppingListRealtime = createShoppingListRealtimeHub();
  const app = createApp({ config, activityStore, shoppingListRealtime });
  const storeHomeAssistantPhoneActivity = (event: HomeAssistantStateChangedEvent) => {
    if (!shouldIncludePhoneStateChangedEvent(event)) {
      return;
    }

    const normalizedEvent = normalizePhoneStateChangedEvent(event);

    activityStore.add(normalizedEvent);

    if (event.ingestionSource !== 'history') {
      console.info(`Home Assistant phone activity stored ${normalizedEvent.entityId}.`);
    }
  };
  const activityListener = createHomeAssistantActivityListener(config, {
    onStateChanged: storeHomeAssistantPhoneActivity,
  });

  const server = app.listen(config.port, () => {
    console.log(`Levy Home API listening on http://localhost:${config.port}`);
    activityListener?.start();
    void backfillHomeAssistantActivity(config, {
      onStateChanged: storeHomeAssistantPhoneActivity,
    })
      .then((eventCount) => {
        if (eventCount > 0) {
          console.info(`Home Assistant activity backfill stored ${eventCount} event(s) from the last 24 hours.`);
        }
      })
      .catch((error) => {
        console.warn(`Home Assistant activity backfill failed: ${safeErrorMessage(error)}`);
      });
  });

  server.on('close', () => {
    activityListener?.stop();
    shoppingListRealtime.close();
  });

  server.on('upgrade', (request, socket, head) => {
    if (shoppingListRealtime.handleUpgrade(request, socket, head)) {
      return;
    }

    socket.write('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    socket.destroy();
  });

  let isShuttingDown = false;
  const shutdown = (signal: NodeJS.Signals) => {
    if (isShuttingDown) {
      return;
    }

    isShuttingDown = true;
    console.info(`Levy Home API received ${signal}. gracefully shutting down previous deployment.`);

    const forceExit = setTimeout(() => {
      process.exit(1);
    }, 10_000);
    forceExit.unref();

    shoppingListRealtime.close();

    server.close((error) => {
      if (error) {
        console.error(`Levy Home API shutdown failed: ${safeErrorMessage(error)}`);
        process.exit(1);
      }

      clearTimeout(forceExit);
      process.exit(0);
    });
  };

  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}

function safeErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Unknown error.';
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
