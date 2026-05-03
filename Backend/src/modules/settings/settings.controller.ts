import { Request, Response, NextFunction } from 'express';
import * as settingsService from './settings.service';
import { sendSuccess } from '../../utils/response';

export async function listSettings(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, await settingsService.listSettings());
  } catch (err) { next(err); }
}

export async function updateSetting(req: Request, res: Response, next: NextFunction) {
  try {
    const updated = await settingsService.updateSetting(req.params.key, req.body.value, req.user!.id);
    sendSuccess(res, updated);
  } catch (err) { next(err); }
}
