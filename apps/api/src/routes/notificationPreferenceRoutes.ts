import { Router } from 'express';

import {
  type NotificationPreferenceState,
  preferenceKeyForLocator,
  type RegisteredDeviceState,
} from './routeState.js';
import {
  GARAGE_NOTIFICATION_PREFERENCES,
  type NotificationPreference,
  type NotificationPreferenceUpdate,
} from '../contracts.js';
import {
  validateNotificationPreferencesBody,
  validateNotificationPreferencesQuery,
} from '../validation.js';

export type NotificationPreferenceRouteDependencies = Pick<RegisteredDeviceState, 'registeredDevicesById'> &
  NotificationPreferenceState;

export function createNotificationPreferenceRoutes(
  deps: NotificationPreferenceRouteDependencies,
): Router {
  const router = Router();

  router.get('/api/notification-preferences', (req, res) => {
    const locator = validateNotificationPreferencesQuery(req.query);
    const preferences = locator
      ? (deps.preferencesByDeviceKey.get(preferenceKeyForLocator(locator, deps.registeredDevicesById)) ??
        GARAGE_NOTIFICATION_PREFERENCES)
      : GARAGE_NOTIFICATION_PREFERENCES;

    res.json({
      ok: true,
      preferences,
      syncedAt: new Date().toISOString(),
    });
  });

  router.put('/api/notification-preferences', (req, res) => {
    const update = validateNotificationPreferencesBody(req.body);
    const deviceKey = preferenceKeyForLocator(update.locator, deps.registeredDevicesById);
    const preferences = applyPreferenceUpdates(GARAGE_NOTIFICATION_PREFERENCES, update.preferences);

    deps.preferencesByDeviceKey.set(deviceKey, preferences);

    res.json({
      ok: true,
      preferences,
      syncedAt: new Date().toISOString(),
    });
  });

  return router;
}

function applyPreferenceUpdates(
  defaults: NotificationPreference[],
  updates: NotificationPreferenceUpdate[],
): NotificationPreference[] {
  const enabledByCategory = new Map(updates.map((update) => [update.category, update.isEnabled]));

  return defaults.map((preference) => ({
    ...preference,
    isEnabled: enabledByCategory.get(preference.category) ?? preference.isEnabled,
  }));
}
