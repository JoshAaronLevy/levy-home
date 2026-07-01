import { Router } from 'express';

import type { AppConfig } from '../config.js';
import type { HomeService } from '../homeService.js';
import { asyncHandler } from '../http/asyncHandler.js';
import { validateQuickActionBody } from '../validation.js';

export type HomeRouteDependencies = {
  config: AppConfig;
  homeService: HomeService;
};

export function createHomeRoutes(deps: HomeRouteDependencies): Router {
  const router = Router();

  router.get(
    '/api/home/overview',
    asyncHandler(async (_req, res) => {
      res.json({
        ok: true,
        overview: await deps.homeService.getOverview(),
      });
    }),
  );

  router.get('/api/home/actions', (_req, res) => {
    res.json({
      ok: true,
      actions: deps.homeService.listQuickActions(),
      lightGroups: lightActionTargets(deps.config).map(({ id, name }) => ({ id, name })),
    });
  });

  router.post(
    '/api/home/actions',
    asyncHandler(async (req, res) => {
      const action = validateQuickActionBody(req.body);
      const result = await deps.homeService.performAction(action.actionId, action.groupId);

      res.json({
        ok: true,
        result,
      });
    }),
  );

  router.post(
    '/api/home/actions/open-garage',
    asyncHandler(async (_req, res) => {
      const result = await deps.homeService.performAction('open_garage');

      res.json({
        ok: true,
        result,
      });
    }),
  );

  router.post(
    '/api/home/actions/close-garage',
    asyncHandler(async (_req, res) => {
      const result = await deps.homeService.performAction('close_garage');

      res.json({
        ok: true,
        result,
      });
    }),
  );

  router.post(
    '/api/home/actions/lights-off',
    asyncHandler(async (_req, res) => {
      const result = await deps.homeService.performAction('turn_off_all_lights');

      res.json({
        ok: true,
        result,
      });
    }),
  );

  router.post(
    '/api/home/actions/light-groups/:groupId/off',
    asyncHandler(async (req, res) => {
      const groupId = typeof req.params.groupId === 'string' ? req.params.groupId : undefined;
      const result = await deps.homeService.performAction('turn_off_light_group', groupId);

      res.json({
        ok: true,
        result,
      });
    }),
  );

  return router;
}

function lightActionTargets(config: AppConfig): Array<{ id: string; name: string }> {
  return config.homeAssistant.lightEntities.length > 0
    ? config.homeAssistant.lightEntities
    : config.homeAssistant.lightGroups;
}
