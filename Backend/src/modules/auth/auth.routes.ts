import { Router } from 'express';
import * as controller from './auth.controller';
import { authenticate } from '../../middleware/auth.middleware';

const router = Router();

/**
 * @openapi
 * /auth/google:
 *   get:
 *     tags: [Auth]
 *     summary: Redirect to Google OAuth consent screen
 *     security: []
 *     responses:
 *       302:
 *         description: Redirects the browser to Google's OAuth page
 */
router.get('/google', controller.googleLogin);

/**
 * @openapi
 * /auth/google/callback:
 *   get:
 *     tags: [Auth]
 *     summary: Google OAuth callback — exchanges code for tokens
 *     description: >
 *       Google redirects here after the user grants access.
 *       Returns an access token in the JSON body and sets the refresh token
 *       as an httpOnly cookie.
 *     security: []
 *     parameters:
 *       - name: code
 *         in: query
 *         required: true
 *         schema: { type: string }
 *         description: Authorization code from Google
 *     responses:
 *       200:
 *         description: Authentication successful
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   $ref: '#/components/schemas/AuthResponse'
 *             example:
 *               success: true
 *               data:
 *                 accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1dWlkLWhlcmUiLCJlbWFpbCI6InVzZXJAZXhhbXBsZS5jb20iLCJyb2xlcyI6WyJTYWxlcyBPZmZpY2VyIl0sInBlcm1pc3Npb25zIjpbIm9yZGVycy5jcmVhdGUiXSwiaWF0IjoxNzE0MDAwMDAwLCJleHAiOjE3MTQwMDA5MDB9.signature"
 *                 user:
 *                   id: "550e8400-e29b-41d4-a716-446655440000"
 *                   email: "user@example.com"
 *                   name: "Rahul Sharma"
 *                   avatarUrl: "https://lh3.googleusercontent.com/a/photo"
 *                   roles: ["Sales Officer"]
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 */
router.get('/google/callback', controller.googleCallback);

/**
 * @openapi
 * /auth/refresh:
 *   post:
 *     tags: [Auth]
 *     summary: Obtain a new access token using the refresh token
 *     description: >
 *       Reads the refresh token from the `refreshToken` httpOnly cookie.
 *       Alternatively accepts `{ "refreshToken": "..." }` in the request body.
 *     security: []
 *     requestBody:
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               refreshToken:
 *                 type: string
 *                 description: Only required if the httpOnly cookie is not available
 *     responses:
 *       200:
 *         description: New access token issued
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: object
 *                   properties:
 *                     accessToken: { type: string }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 */
router.post('/refresh', controller.refresh);

/**
 * @openapi
 * /auth/logout:
 *   post:
 *     tags: [Auth]
 *     summary: Clear the refresh token cookie
 *     security: []
 *     responses:
 *       200:
 *         description: Logged out successfully
 */
router.post('/logout', controller.logout);

/**
 * @openapi
 * /auth/me:
 *   get:
 *     tags: [Auth]
 *     summary: Get the currently authenticated user's identity
 *     responses:
 *       200:
 *         description: Current user from the access token
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data:
 *                   type: object
 *                   properties:
 *                     id: { type: string, format: uuid }
 *                     email: { type: string }
 *                     roles: { type: array, items: { type: string } }
 *                     permissions: { type: array, items: { type: string } }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 */
router.get('/me', authenticate, controller.me);

/**
 * @openapi
 * /auth/google/id-token:
 *   post:
 *     tags: [Auth]
 *     summary: Authenticate using a Google ID token (Flutter / mobile)
 *     security: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [idToken]
 *             properties:
 *               idToken: { type: string }
 *     responses:
 *       200:
 *         description: Authentication successful
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success: { type: boolean, example: true }
 *                 data: { $ref: '#/components/schemas/AuthResponse' }
 *       401:
 *         $ref: '#/components/responses/Unauthorized'
 */
router.post('/google/id-token', controller.googleIdToken);

export default router;
