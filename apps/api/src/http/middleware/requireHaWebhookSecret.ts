import type { NextFunction, Request, Response } from 'express';

import type { AppConfig } from '../../config.js';

export function requireHaWebhookSecret(config: AppConfig): (req: Request, res: Response, next: NextFunction) => void {
  return (req, res, next) => {
    if (!config.haWebhookSecret) {
      res.status(500).json({
        error: 'LEVY_HOME_HA_WEBHOOK_SECRET is not configured.',
        code: 'webhook_secret_not_configured',
      });
      return;
    }

    if (req.header('Authorization') !== `Bearer ${config.haWebhookSecret}`) {
      res.status(401).json({
        error: 'Unauthorized Home Assistant event webhook.',
        code: 'unauthorized_home_assistant_webhook',
      });
      return;
    }

    next();
  };
}
