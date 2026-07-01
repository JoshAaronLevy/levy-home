import { Router } from 'express';

import type { UsersResponse } from '../contracts.js';
import { asyncHandler } from '../http/asyncHandler.js';
import type { UserStore } from '../repositories/userRepository.js';

export type UserRouteDependencies = {
  userStore: UserStore;
};

export function createUserRoutes(deps: UserRouteDependencies): Router {
  const router = Router();

  router.get('/api/users', asyncHandler(async (_req, res) => {
    const response: UsersResponse = {
      ok: true,
      users: await deps.userStore.fetchUsers(),
      generatedAt: new Date().toISOString(),
    };

    res.json(response);
  }));

  return router;
}
