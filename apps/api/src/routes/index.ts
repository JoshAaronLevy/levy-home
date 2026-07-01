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
import type { ShoppingListStore } from '../repositories/shoppingListRepository.js';
import type { ToDoLocationStore } from '../repositories/todoLocationRepository.js';
import type { UserStore } from '../repositories/userRepository.js';
import { createActivityRoutes } from './activityRoutes.js';
import { createDebugRoutes } from './debugRoutes.js';
import { createDeviceRoutes } from './deviceRoutes.js';
import { createHealthRoutes } from './healthRoutes.js';
import { createHomeRoutes } from './homeRoutes.js';
import { createNotificationPreferenceRoutes } from './notificationPreferenceRoutes.js';
import { createShoppingListRoutes } from './shoppingListRoutes.js';
import { createToDoLocationRoutes } from './todoLocationRoutes.js';
import { createUserRoutes } from './userRoutes.js';

export type AppRouteDependencies = {
  activityEventService: ActivityEventService;
  activityStore: RecentActivityStore;
  config: AppConfig;
  deviceRegistry: DeviceRegistry;
  homeAssistant: HomeAssistantFacade;
  homeService: HomeService;
  krogerProductDiagnosticRunner: KrogerProductDiagnosticRunner;
  krogerProductSearchRunner: (query?: string) => Promise<KrogerProductSearchResponse>;
  notificationPreferenceStore: NotificationPreferenceStore;
  notificationService: NotificationService;
  shoppingListMutationService: ShoppingListMutationService;
  shoppingListStore: ShoppingListStore;
  toDoLocationStore: ToDoLocationStore;
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
  app.use(createShoppingListRoutes(deps));
  app.use(createActivityRoutes(deps));
}
