import type { NextFunction, Request, Response } from 'express';

export function noStoreCacheControl(_req: Request, res: Response, next: NextFunction): void {
  res.set('Cache-Control', 'no-store');
  next();
}
