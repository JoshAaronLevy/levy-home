import { Router } from 'express';

import type { NotificationPreferenceStore } from '../services/notifications/notificationPreferenceStore.js';
import {
  validateNotificationPreferencesBody,
  validateNotificationPreferencesQuery,
} from '../validation.js';

export type NotificationPreferenceRouteDependencies = {
  notificationPreferenceStore: NotificationPreferenceStore;
};

export function createNotificationPreferenceRoutes(
  deps: NotificationPreferenceRouteDependencies,
): Router {
  const router = Router();

  router.get('/api/notification-preferences', (req, res) => {
    const locator = validateNotificationPreferencesQuery(req.query);

    res.json({
      ok: true,
      preferences: deps.notificationPreferenceStore.getPreferences(locator),
      syncedAt: new Date().toISOString(),
    });
  });

  router.put('/api/notification-preferences', (req, res) => {
    const update = validateNotificationPreferencesBody(req.body);

    res.json({
      ok: true,
      preferences: deps.notificationPreferenceStore.updatePreferences(update),
      syncedAt: new Date().toISOString(),
    });
  });

  return router;
}
