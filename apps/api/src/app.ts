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
import { DatabaseConfigurationError, isDatabaseConfigured } from './db/client.js';
import { createHomeAssistantFacade } from './integrations/homeAssistant/facade.js';
import { HomeService } from './homeService.js';
import { HTTPError } from './http/errors.js';
import { noStoreCacheControl } from './http/middleware/cacheControl.js';
import { lookupAndWriteKrogerProductResponse, type KrogerProductDiagnosticRunner } from './integrations/kroger/productDiagnostics.js';
import { searchKrogerProducts } from './integrations/kroger/productClient.js';
import { logger, type Logger, safeErrorMessage } from './observability/logger.js';
import { registerRoutes } from './routes/index.js';
import type { NotificationPersistenceMode } from './routes/healthRoutes.js';
import { createPostgresShoppingListStore, type ShoppingListStore } from './repositories/shoppingListRepository.js';
import {
  createPostgresToDoLocationStore,
  type ToDoLocationStore,
} from './repositories/todoLocationRepository.js';
import { createPostgresToDoListStore, type ToDoListStore } from './repositories/todoListRepository.js';
import { createPostgresUserStore, type UserStore } from './repositories/userRepository.js';
import { createActivityEventService } from './services/activity/activityEventService.js';
import {
  createInMemoryDeviceRegistry,
  createPostgresDeviceRegistry,
  type DeviceRegistry,
} from './services/notifications/deviceRegistry.js';
import {
  createInMemoryNotificationPreferenceStore,
  createPostgresNotificationPreferenceStore,
  type NotificationPreferenceStore,
} from './services/notifications/notificationPreferenceStore.js';
import { createNotificationService } from './services/notifications/notificationService.js';
import { createShoppingListMutationService } from './services/shopping/shoppingListMutationService.js';
import { createToDoListMutationService, type ToDoListMutationService } from './services/todo/todoListMutationService.js';
import type { ShoppingListRealtimeBroadcaster } from './shoppingListRealtime.js';
import { createToDoListRealtimeHub, type ToDoListRealtimeHub } from './todoListRealtime.js';

export type CreateAppOptions = {
  config?: AppConfig;
  activityStore?: RecentActivityStore;
  logger?: Logger;
  pushSender?: PushSender;
  deviceRegistry?: DeviceRegistry;
  notificationPreferenceStore?: NotificationPreferenceStore;
  shoppingListStore?: ShoppingListStore;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  toDoListRealtime?: ToDoListRealtimeHub;
  userStore?: UserStore;
  toDoLocationStore?: ToDoLocationStore;
  toDoListStore?: ToDoListStore;
  toDoListMutationService?: ToDoListMutationService;
  krogerProductDiagnosticRunner?: KrogerProductDiagnosticRunner;
  krogerProductSearchRunner?: (query?: string) => Promise<KrogerProductSearchResponse>;
  notificationPersistenceMode?: NotificationPersistenceMode;
};

export function createApp(options: CreateAppOptions = {}): express.Express {
  const config = options.config ?? readConfig();
  const app = express();
  const appLogger = options.logger ?? logger;
  const activityStore = options.activityStore ?? createRecentActivityStore(500);
  const usePersistentNotificationStores = isDatabaseConfigured();
  const hasInjectedNotificationStores = Boolean(options.deviceRegistry || options.notificationPreferenceStore);
  const notificationPersistenceMode =
    options.notificationPersistenceMode ??
    (hasInjectedNotificationStores || !usePersistentNotificationStores ? 'memory' : 'postgres');
  const deviceRegistry =
    options.deviceRegistry ??
    (notificationPersistenceMode === 'postgres' ? createPostgresDeviceRegistry() : createInMemoryDeviceRegistry());
  const notificationPreferenceStore =
    options.notificationPreferenceStore ??
    (notificationPersistenceMode === 'postgres'
      ? createPostgresNotificationPreferenceStore(deviceRegistry)
      : createInMemoryNotificationPreferenceStore(deviceRegistry));
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
    notificationService,
    shoppingListRealtime,
    shoppingListStore,
  });
  const userStore = options.userStore ?? createPostgresUserStore();
  const toDoLocationStore = options.toDoLocationStore ?? createPostgresToDoLocationStore();
  const toDoListStore = options.toDoListStore ?? createPostgresToDoListStore();
  const toDoListRealtime = options.toDoListRealtime ?? createToDoListRealtimeHub({ notificationService });
  const toDoListMutationService =
    options.toDoListMutationService ??
    createToDoListMutationService({
      toDoListRealtime,
      toDoListStore,
    });
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
  app.set('toDoListRealtime', toDoListRealtime);

  registerRoutes(app, {
    activityStore,
    activityEventService,
    config,
    deviceRegistry,
    homeAssistant,
    homeService,
    krogerProductDiagnosticRunner,
    krogerProductSearchRunner,
    notificationPersistenceMode,
    notificationPreferenceStore,
    notificationService,
    shoppingListMutationService,
    shoppingListStore,
    toDoLocationStore,
    toDoListMutationService,
    toDoListStore,
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

    appLogger.error('Unexpected API error.', { error: safeErrorMessage(err) });
    res.status(500).json({ error: 'Unexpected server error.', code: 'unexpected_server_error' });
  });

  return app;
}
