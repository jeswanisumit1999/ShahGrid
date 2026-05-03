import { Request, Response, NextFunction } from 'express';
import * as authService from './auth.service';
import { sendSuccess } from '../../utils/response';
import { env } from '../../config/env';

export async function googleLogin(req: Request, res: Response, next: NextFunction) {
  try {
    const url = authService.getGoogleAuthUrl();
    res.redirect(url);
  } catch (err) {
    next(err);
  }
}

export async function googleCallback(req: Request, res: Response, next: NextFunction) {
  try {
    const code = req.query.code as string;
    const result = await authService.exchangeGoogleCode(code);

    // Build redirect URL for Flutter web app
    const callbackUrl = new URL(`${env.FRONTEND_URL}/auth/callback`);
    callbackUrl.searchParams.set('accessToken', result.accessToken);
    callbackUrl.searchParams.set('refreshToken', result.refreshToken);

    // Also set httpOnly cookie (useful when frontend is same-origin in prod)
    res.cookie('refreshToken', result.refreshToken, {
      httpOnly: true,
      secure: env.NODE_ENV === 'production',
      sameSite: 'lax', // lax so the cookie survives the cross-origin redirect
      maxAge: 30 * 24 * 60 * 60 * 1000,
    });

    res.redirect(callbackUrl.toString());
  } catch (err) {
    next(err);
  }
}

export async function refresh(req: Request, res: Response, next: NextFunction) {
  try {
    const token = req.cookies?.refreshToken ?? req.body?.refreshToken;
    const result = await authService.refreshAccessToken(token);
    sendSuccess(res, result);
  } catch (err) {
    next(err);
  }
}

export async function logout(_req: Request, res: Response, next: NextFunction) {
  try {
    res.clearCookie('refreshToken');
    sendSuccess(res, { message: 'Logged out' });
  } catch (err) {
    next(err);
  }
}

export async function me(req: Request, res: Response, next: NextFunction) {
  try {
    sendSuccess(res, req.user);
  } catch (err) {
    next(err);
  }
}

// Flutter: google_sign_in sends idToken directly, skipping the browser OAuth redirect
export async function googleIdToken(req: Request, res: Response, next: NextFunction) {
  try {
    const { idToken } = req.body as { idToken: string };
    const result = await authService.verifyGoogleIdToken(idToken);

    res.cookie('refreshToken', result.refreshToken, {
      httpOnly: true,
      secure: env.NODE_ENV === 'production',
      sameSite: 'strict',
      maxAge: 30 * 24 * 60 * 60 * 1000,
    });

    sendSuccess(res, { accessToken: result.accessToken, user: result.user });
  } catch (err) {
    next(err);
  }
}
