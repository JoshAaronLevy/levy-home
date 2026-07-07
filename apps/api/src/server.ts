import 'dotenv/config';

import { pathToFileURL } from 'node:url';

import {
  normalizePhoneStateChangedEvent,
  shouldIncludePhoneStateChangedEvent,
} from './integrations/homeAssistant/activityNormalizer.js';
import { createRecentActivityStore } from './activityStore.js';
import { createApp } from './app.js';
import { logApnsPrivateKeyStatus, readConfig, type AppConfig } from './config.js';
import { backfillHomeAssistantActivity } from './integrations/homeAssistant/activityBackfill.js';
import {
  createHomeAssistantActivityListener,
  type HomeAssistantStateChangedEvent,
} from './integrations/homeAssistant/activityListener.js';
import { logger, type Logger, safeErrorMessage } from './observability/logger.js';
import { createShoppingListRealtimeHub } from './shoppingListRealtime.js';
import type { ToDoListRealtimeHub } from './todoListRealtime.js';

export function startServer(config?: AppConfig, options: { logger?: Logger } = {}): void {
  const serverLogger = options.logger ?? logger;
  const resolvedConfig = config ?? readConfig();

  logApnsPrivateKeyStatus(resolvedConfig, serverLogger);

  const activityStore = createRecentActivityStore(500);
  const shoppingListRealtime = createShoppingListRealtimeHub();
  const app = createApp({ config: resolvedConfig, activityStore, logger: serverLogger, shoppingListRealtime });
  const toDoListRealtime = app.get('toDoListRealtime') as ToDoListRealtimeHub | undefined;
  const storeHomeAssistantPhoneActivity = (event: HomeAssistantStateChangedEvent) => {
    if (!shouldIncludePhoneStateChangedEvent(event)) {
      return;
    }

    const normalizedEvent = normalizePhoneStateChangedEvent(event);

    activityStore.add(normalizedEvent);

    if (event.ingestionSource !== 'history') {
      serverLogger.info('Home Assistant phone activity stored.', { entityId: normalizedEvent.entityId });
    }
  };
  const activityListener = createHomeAssistantActivityListener(resolvedConfig, {
    logger: serverLogger,
    onStateChanged: storeHomeAssistantPhoneActivity,
  });

  const server = app.listen(resolvedConfig.port, () => {
    serverLogger.info('Levy Home API listening.', { port: resolvedConfig.port });
    activityListener?.start();
    void backfillHomeAssistantActivity(resolvedConfig, {
      logger: serverLogger,
      onStateChanged: storeHomeAssistantPhoneActivity,
    })
      .then((eventCount) => {
        if (eventCount > 0) {
          serverLogger.info('Home Assistant activity backfill stored events.', { eventCount });
        }
      })
      .catch((error) => {
        serverLogger.warn('Home Assistant activity backfill failed.', { error: safeErrorMessage(error) });
      });
  });

  server.on('close', () => {
    activityListener?.stop();
    shoppingListRealtime.close();
    toDoListRealtime?.close();
  });

  server.on('upgrade', (request, socket, head) => {
    if (shoppingListRealtime.handleUpgrade(request, socket, head)) {
      return;
    }

    if (toDoListRealtime?.handleUpgrade(request, socket, head)) {
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
    serverLogger.info('Levy Home API received shutdown signal; gracefully shutting down previous deployment.', {
      signal,
    });

    const forceExit = setTimeout(() => {
      process.exit(1);
    }, 10_000);
    forceExit.unref();

    shoppingListRealtime.close();
    toDoListRealtime?.close();

    server.close((error) => {
      if (error) {
        serverLogger.error('Levy Home API shutdown failed.', { error: safeErrorMessage(error) });
        process.exit(1);
      }

      clearTimeout(forceExit);
      process.exit(0);
    });
  };

  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  startServer();
}
