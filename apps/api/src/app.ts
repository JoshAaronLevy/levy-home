import cors from 'cors';
import express, { type NextFunction, type Request, type Response } from 'express';

import {
  createRecentActivityStore,
  type RecentActivityStore,
} from './activityStore.js';
import {
  createAPNsPushSender,
  createAPNsShoppingLiveActivityPushSender,
  type PushSender,
  type ShoppingLiveActivityPushSender,
} from './integrations/apple/apnsPushSender.js';
import type { AppConfig } from './config.js';
import { readConfig } from './config.js';
import type { KrogerProductSearchResponse } from './contracts.js';
import {
  DatabaseConfigurationError,
  getDatabaseTransactionRunner,
  isDatabaseConfigured,
  type DatabaseTransactionRunner,
} from './db/client.js';
import { createHomeAssistantFacade } from './integrations/homeAssistant/facade.js';
import { createCameraFacade } from './integrations/homeAssistant/cameraFacade.js';
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
  createPostgresShoppingStockPriceCheckStore,
  type ShoppingStockPriceCheckStore,
} from './repositories/shoppingStockPriceCheckRepository.js';
import { createPostgresShoppingTripStore, type ShoppingTripStore } from './repositories/shoppingTripRepository.js';
import {
  createPostgresShoppingLiveActivityStore,
  type ShoppingLiveActivityStore,
} from './repositories/shoppingLiveActivityRepository.js';
import {
  createPostgresShoppingTripSummaryStore,
  type ShoppingTripSummaryStore,
} from './repositories/shoppingTripSummaryRepository.js';
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
import {
  CodexShoppingWebsiteResearcher,
} from './services/shopping/codexShoppingWebsiteResearcher.js';
import type { RetailerWebsiteResearcher } from './services/shopping/retailerWebsiteResearcher.js';
import {
  createShoppingStockPriceCheckReadiness,
  type ShoppingStockPriceCheckReadiness,
} from './services/shopping/stockPriceCheckReadiness.js';
import { createStockPriceCheckRunner, type StockPriceCheckRunner } from './services/shopping/stockPriceCheckRunner.js';
import { createStockPriceCheckService, type StockPriceCheckService } from './services/shopping/stockPriceCheckService.js';
import { createShoppingTripService, type ShoppingTripService } from './services/shopping/shoppingTripService.js';
import {
  createShoppingLiveActivityDeliveryService,
  type ShoppingLiveActivityDeliveryService,
} from './services/shopping/shoppingLiveActivityDeliveryService.js';
import {
  createShoppingTripSummaryDeliveryService,
  type ShoppingTripSummaryDeliveryService,
} from './services/shopping/shoppingTripSummaryDeliveryService.js';
import { createToDoListMutationService, type ToDoListMutationService } from './services/todo/todoListMutationService.js';
import {
  createWeatherAlertService,
  type WeatherAlertService,
} from './services/weather/weatherAlertService.js';
import { createDoorbellImageService } from './services/doorbell/doorbellImageService.js';
import { CameraService } from './services/camera/cameraService.js';
import {
  createShoppingListRealtimeHub,
  type ShoppingListRealtimeBroadcaster,
} from './shoppingListRealtime.js';
import { createToDoListRealtimeHub, type ToDoListRealtimeHub } from './todoListRealtime.js';

export type CreateAppOptions = {
  config?: AppConfig;
  activityStore?: RecentActivityStore;
  logger?: Logger;
  pushSender?: PushSender;
  deviceRegistry?: DeviceRegistry;
  notificationPreferenceStore?: NotificationPreferenceStore;
  shoppingListStore?: ShoppingListStore;
  shoppingTripStore?: ShoppingTripStore;
  shoppingMutationTransactionRunner?: DatabaseTransactionRunner;
  shoppingLiveActivityStore?: ShoppingLiveActivityStore;
  shoppingLiveActivityPushSender?: ShoppingLiveActivityPushSender;
  shoppingLiveActivityDeliveryService?: ShoppingLiveActivityDeliveryService;
  shoppingTripSummaryStore?: ShoppingTripSummaryStore;
  shoppingTripSummaryDeliveryService?: ShoppingTripSummaryDeliveryService;
  shoppingListRealtime?: ShoppingListRealtimeBroadcaster;
  shoppingStockPriceCheckStore?: ShoppingStockPriceCheckStore;
  retailerWebsiteResearcher?: RetailerWebsiteResearcher;
  stockPriceCheckService?: StockPriceCheckService;
  stockPriceCheckRunner?: StockPriceCheckRunner;
  shoppingStockPriceCheckReadiness?: ShoppingStockPriceCheckReadiness;
  toDoListRealtime?: ToDoListRealtimeHub;
  userStore?: UserStore;
  toDoLocationStore?: ToDoLocationStore;
  toDoListStore?: ToDoListStore;
  toDoListMutationService?: ToDoListMutationService;
  weatherAlertService?: WeatherAlertService;
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
  const cameraService = new CameraService(createCameraFacade(config));
  const homeService = new HomeService(config, homeAssistant, () => activityStore.list(100));
  const pushSender = options.pushSender ?? createAPNsPushSender(config);
  const notificationService = createNotificationService({
    deviceRegistry,
    notificationPreferenceStore,
    pushSender,
  });
  const weatherAlertService = options.weatherAlertService ?? createWeatherAlertService({
    config: config.weatherAlerts,
    notificationService,
    logger: appLogger,
  });
  const activityEventService = createActivityEventService({ notificationService });
  const doorbellImageService = createDoorbellImageService(config);
  const shoppingListStore = options.shoppingListStore ?? createPostgresShoppingListStore();
  const shoppingListRealtime = options.shoppingListRealtime ?? createShoppingListRealtimeHub({ notificationService });
  const shoppingTripStore = options.shoppingTripStore ?? (
    isDatabaseConfigured() ? createPostgresShoppingTripStore() : undefined
  );
  const shoppingLiveActivityStore = options.shoppingLiveActivityStore ?? (
    isDatabaseConfigured() ? createPostgresShoppingLiveActivityStore() : undefined
  );
  const shoppingLiveActivityDeliveryService: ShoppingLiveActivityDeliveryService | undefined =
    options.shoppingLiveActivityDeliveryService ?? (shoppingLiveActivityStore && shoppingTripStore
      ? createShoppingLiveActivityDeliveryService({
        logger: appLogger,
        pushSender: options.shoppingLiveActivityPushSender ?? createAPNsShoppingLiveActivityPushSender(config),
        shoppingLiveActivityStore,
        shoppingTripStore,
      })
      : undefined);
  const shoppingTripSummaryStore = options.shoppingTripSummaryStore ?? (
    isDatabaseConfigured() ? createPostgresShoppingTripSummaryStore() : undefined
  );
  const shoppingTripSummaryDeliveryService: ShoppingTripSummaryDeliveryService | undefined =
    options.shoppingTripSummaryDeliveryService ?? (shoppingTripSummaryStore
      ? createShoppingTripSummaryDeliveryService({
        logger: appLogger,
        pushSender,
        deviceRegistry,
        notificationPreferenceStore,
        shoppingTripSummaryStore,
      })
      : undefined);
  const shoppingTripService: ShoppingTripService | undefined = shoppingTripStore
    ? createShoppingTripService({
      shoppingListRealtime,
      shoppingLiveActivityDeliveryService,
      shoppingTripSummaryDeliveryService,
      shoppingTripStore,
    })
    : undefined;
  const shoppingListMutationService = createShoppingListMutationService({
    shoppingListRealtime,
    shoppingListStore,
    shoppingTripService,
    shoppingTripStore,
    ...(options.shoppingMutationTransactionRunner
      ? { transactionRunner: options.shoppingMutationTransactionRunner }
      : shoppingTripStore && isDatabaseConfigured()
        ? { transactionRunner: getDatabaseTransactionRunner() }
      : {}),
    shoppingLiveActivityDeliveryService,
  });
  const shoppingStockPriceCheckStore = options.shoppingStockPriceCheckStore ?? (
    isDatabaseConfigured() ? createPostgresShoppingStockPriceCheckStore() : undefined
  );
  const retailerWebsiteResearcher = options.retailerWebsiteResearcher ?? new CodexShoppingWebsiteResearcher();
  const stockPriceCheckService = options.stockPriceCheckService ?? (shoppingStockPriceCheckStore
    ? createStockPriceCheckService({
      stockPriceCheckStore: shoppingStockPriceCheckStore,
      shoppingListMutationService,
      retailerWebsiteResearcher,
      logger: appLogger,
    })
    : undefined);
  const stockPriceCheckRunner = options.stockPriceCheckRunner ?? (stockPriceCheckService
    ? createStockPriceCheckRunner({
      stockPriceCheckService,
      logger: appLogger,
      fetchActiveRun: () => shoppingStockPriceCheckStore?.fetchActiveRun() ?? Promise.resolve(null),
    })
    : undefined);
  const shoppingStockPriceCheckReadiness = options.shoppingStockPriceCheckReadiness ??
    createShoppingStockPriceCheckReadiness({ shoppingStockPriceCheckStore });
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
  app.set('trust proxy', 1);
  app.use(cors());
  app.use(noStoreCacheControl);
  app.use(express.json({ limit: '1mb' }));
  app.set('shoppingListRealtime', shoppingListRealtime);
  app.set('toDoListRealtime', toDoListRealtime);
  app.set('weatherAlertService', weatherAlertService);
  app.set('shoppingLiveActivityDeliveryService', shoppingLiveActivityDeliveryService);
  app.set('shoppingTripSummaryDeliveryService', shoppingTripSummaryDeliveryService);
  app.set('stockPriceCheckRunner', stockPriceCheckRunner);

  registerRoutes(app, {
    activityStore,
    activityEventService,
    cameraService,
    config,
    doorbellImageService,
    deviceRegistry,
    homeAssistant,
    homeService,
    krogerProductDiagnosticRunner,
    krogerProductSearchRunner,
    logger: appLogger,
    notificationPersistenceMode,
    notificationPreferenceStore,
    notificationService,
    shoppingLiveActivityDeliveryService,
    shoppingLiveActivityStore,
    shoppingListMutationService,
    shoppingListStore,
    shoppingStockPriceCheckReadiness,
    shoppingStockPriceCheckStore,
    stockPriceCheckRunner,
    shoppingTripService,
    shoppingTripStore,
    toDoLocationStore,
    toDoListMutationService,
    toDoListStore,
    userStore,
  });

  // Durable state, rather than an HTTP request-held promise, controls restart
  // recovery. The runner itself de-duplicates in-process schedules.
  stockPriceCheckRunner?.recover();

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
