import type { Express } from 'express';

import type { RecentActivityStore } from '../activityStore.js';
import type { AppConfig } from '../config.js';
import type { KrogerProductSearchResponse } from '../contracts.js';
import type { HomeAssistantFacade } from '../integrations/homeAssistant/facade.js';
import type { HomeService } from '../homeService.js';
import type { KrogerProductDiagnosticRunner } from '../integrations/kroger/productDiagnostics.js';
import type { ActivityEventService } from '../services/activity/activityEventService.js';
import type { DeviceRegistry } from '../services/notifications/deviceRegistry.js';
import type { NotificationPreferenceStore } from '../services/notifications/notificationPreferenceStore.js';
import type { NotificationService } from '../services/notifications/notificationService.js';
import type { ShoppingListMutationService } from '../services/shopping/shoppingListMutationService.js';
import type { ShoppingTripService } from '../services/shopping/shoppingTripService.js';
import type { ShoppingLiveActivityDeliveryService } from '../services/shopping/shoppingLiveActivityDeliveryService.js';
import type { ShoppingListStore } from '../repositories/shoppingListRepository.js';
import type { ShoppingTripStore } from '../repositories/shoppingTripRepository.js';
import type { ShoppingLiveActivityStore } from '../repositories/shoppingLiveActivityRepository.js';
import type { ToDoLocationStore } from '../repositories/todoLocationRepository.js';
import type { ToDoListStore } from '../repositories/todoListRepository.js';
import type { ToDoListMutationService } from '../services/todo/todoListMutationService.js';
import type { UserStore } from '../repositories/userRepository.js';
import type { DoorbellImageService } from '../services/doorbell/doorbellImageService.js';
import { createActivityRoutes } from './activityRoutes.js';
import { createDebugRoutes } from './debugRoutes.js';
import { createDeviceRoutes } from './deviceRoutes.js';
import { createHealthRoutes, type NotificationPersistenceMode } from './healthRoutes.js';
import { createHomeRoutes } from './homeRoutes.js';
import { createNotificationPreferenceRoutes } from './notificationPreferenceRoutes.js';
import { createShoppingListRoutes } from './shoppingListRoutes.js';
import { createShoppingTripRoutes } from './shoppingTripRoutes.js';
import { createShoppingLiveActivityRoutes } from './shoppingLiveActivityRoutes.js';
import { createToDoLocationRoutes } from './todoLocationRoutes.js';
import { createToDoListRoutes } from './todoListRoutes.js';
import { createUserRoutes } from './userRoutes.js';

export type AppRouteDependencies = {
  activityEventService: ActivityEventService;
  activityStore: RecentActivityStore;
  config: AppConfig;
  doorbellImageService: DoorbellImageService;
  deviceRegistry: DeviceRegistry;
  homeAssistant: HomeAssistantFacade;
  homeService: HomeService;
  krogerProductDiagnosticRunner: KrogerProductDiagnosticRunner;
  krogerProductSearchRunner: (query?: string) => Promise<KrogerProductSearchResponse>;
  notificationPersistenceMode: NotificationPersistenceMode;
  notificationPreferenceStore: NotificationPreferenceStore;
  notificationService: NotificationService;
  shoppingListMutationService: ShoppingListMutationService;
  shoppingListStore: ShoppingListStore;
  shoppingTripService?: ShoppingTripService;
  shoppingLiveActivityDeliveryService?: ShoppingLiveActivityDeliveryService;
  shoppingLiveActivityStore?: ShoppingLiveActivityStore;
  shoppingTripStore?: ShoppingTripStore;
  toDoLocationStore: ToDoLocationStore;
  toDoListMutationService: ToDoListMutationService;
  toDoListStore: ToDoListStore;
  userStore: UserStore;
};

export function registerRoutes(app: Express, deps: AppRouteDependencies): void {
  app.use(createHealthRoutes(deps));
  app.use(createDeviceRoutes(deps));
  app.use(createNotificationPreferenceRoutes(deps));
  app.use(createDebugRoutes(deps));
  app.use(createHomeRoutes(deps));
  app.use(createUserRoutes(deps));
  app.use(createToDoLocationRoutes(deps));
  app.use(createToDoListRoutes(deps));
  app.use(createShoppingListRoutes(deps));
  app.use(createShoppingTripRoutes(deps));
  app.use(createShoppingLiveActivityRoutes(deps));
  app.use(createActivityRoutes(deps));
  app.get('/api/doorbell-images/:id', (req, res) => {
    const image = deps.doorbellImageService.read(
      req.params.id,
      typeof req.query.expires === 'string' ? req.query.expires : undefined,
      typeof req.query.signature === 'string' ? req.query.signature : undefined,
    );
    if (!image) { res.sendStatus(404); return; }
    res.type(image.contentType).send(image.bytes);
  });
}
