import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';

import {
  createRecentActivityStore,
  type RecentActivityStore,
} from './activityStore.js';
import { createAPNsPushSender, type PushSender } from './integrations/apple/apnsPushSender.js';
import type { AppConfig } from './config.js';
import { readConfig } from './config.js';
import type { KrogerProductSearchResponse } from './contracts.js';
import { DatabaseConfigurationError } from './dbClient.js';
import { createHomeAssistantFacade } from './integrations/homeAssistant/facade.js';
import { HomeService } from './homeService.js';
import { HTTPError } from './http/errors.js';
import { noStoreCacheControl } from './http/middleware/cacheControl.js';
import { lookupAndWriteKrogerProductResponse, type KrogerProductDiagnosticRunner } from './integrations/kroger/productDiagnostics.js';
import { searchKrogerProducts } from './integrations/kroger/productClient.js';
import { registerRoutes } from './routes/index.js';
import { createActivityEventService } from './services/activity/activityEventService.js';
import { createInMemoryDeviceRegistry } from './services/notifications/deviceRegistry.js';
import { createInMemoryNotificationPreferenceStore } from './services/notifications/notificationPreferenceStore.js';
import { createNotificationService } from './services/notifications/notificationService.js';
import { createShoppingListMutationService } from './services/shopping/shoppingListMutationService.js';
import { createPostgresShoppingListStore, type ShoppingListStore } from './shoppingListStore.js';
import type { ShoppingListRealtimeBroadcaster } from './shoppingListRealtime.js';
import {
  createPostgresToDoLocationStore,
  type ToDoLocationStore,
} from './todoLocationStore.js';
import { createPostgresUserStore, type UserStore } from './userStore.js';

export type CreateAppOptions = {
  config?: AppConfig;
  activityStore?: RecentActivityStore;
  pushSender?: PushSender;
  shoppingListStore?: ShoppingListStore;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  userStore?: UserStore;
  toDoLocationStore?: ToDoLocationStore;
  krogerProductDiagnosticRunner?: KrogerProductDiagnosticRunner;
  krogerProductSearchRunner?: (query?: string) => Promise<KrogerProductSearchResponse>;
};

export function createApp(options: CreateAppOptions = {}): express.Express {
  const config = options.config ?? readConfig();
  const app = express();
  const activityStore = options.activityStore ?? createRecentActivityStore(500);
  const deviceRegistry = createInMemoryDeviceRegistry();
  const notificationPreferenceStore = createInMemoryNotificationPreferenceStore(deviceRegistry);
  const homeAssistant = createHomeAssistantFacade(config);
  const homeService = new HomeService(config, homeAssistant, () => activityStore.list(100));
  const pushSender = options.pushSender ?? createAPNsPushSender(config);
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });
  const activityEventService = createActivityEventService({ notificationService });
  const shoppingListStore = options.shoppingListStore ?? createPostgresShoppingListStore();
  const shoppingListRealtime = options.shoppingListRealtime;
  const shoppingListMutationService = createShoppingListMutationService({
    shoppingListRealtime,
    shoppingListStore,
  });
  const userStore = options.userStore ?? createPostgresUserStore();
  const toDoLocationStore = options.toDoLocationStore ?? createPostgresToDoLocationStore();
  const krogerProductDiagnosticRunner =
    options.krogerProductDiagnosticRunner ??
    ((query?: string) => lookupAndWriteKrogerProductResponse(config, { query }));
  const krogerProductSearchRunner =
    options.krogerProductSearchRunner ??
    ((query?: string) => searchKrogerProducts(config, { query }));

  app.set('etag', false);
  app.use(cors());
  app.use(noStoreCacheControl);
  app.use(express.json({ limit: '1mb' }));

  registerRoutes(app, {
    activityStore,
    activityEventService,
    config,
    deviceRegistry,
    homeAssistant,
    homeService,
    krogerProductDiagnosticRunner,
    krogerProductSearchRunner,
    notificationPreferenceStore,
    notificationService,
    shoppingListMutationService,
    shoppingListStore,
    toDoLocationStore,
    userStore,
  });

  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof DatabaseConfigurationError) {
      res.status(503).json({
        error: err.message,
        code: 'database_not_configured',
      });
      return;
    }

    if (err instanceof HTTPError) {
      res.status(err.statusCode).json({
        error: err.message,
        ...(err.code ? { code: err.code } : {}),
      });
      return;
    }

    console.error(err);
    res.status(500).json({ error: 'Unexpected server error.', code: 'unexpected_server_error' });
  });

  return app;
}
