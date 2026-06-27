import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import morgan from 'morgan';
import cookieParser from 'cookie-parser';
import rateLimit from 'express-rate-limit';
import swaggerUi from 'swagger-ui-express';

import { env } from './config/env';
import { swaggerSpec } from './config/swagger';
import { errorHandler } from './middleware/error.middleware';
import { logger } from './utils/logger';

import authRoutes from './modules/auth/auth.routes';
import usersRoutes from './modules/users/users.routes';
import retailersRoutes from './modules/retailers/retailers.routes';
import productsRoutes from './modules/products/products.routes';
import ordersRoutes from './modules/orders/orders.routes';
import challansRoutes from './modules/challans/challans.routes';
import shipmentsRoutes from './modules/shipments/shipments.routes';
import paymentsRoutes from './modules/payments/payments.routes';
import returnsRoutes from './modules/returns/returns.routes';
import visitsRoutes from './modules/visits/visits.routes';
import checkInsRoutes from './modules/checkins/checkins.routes';
import analyticsRoutes from './modules/analytics/analytics.routes';
import settingsRoutes from './modules/settings/settings.routes';
import directSalesRoutes from './modules/direct-sales/direct-sales.routes';

const app = express();

// Behind the Caddy reverse proxy: trust the first proxy hop so req.ip and the
// X-Forwarded-* headers reflect the real client (correct rate-limit keys + logs).
app.set('trust proxy', 1);

// ── Swagger UI ────────────────────────────────────────────────────────────────
// Mounted BEFORE helmet so the UI's inline scripts/styles are not blocked by CSP.
// Available at /api-docs (all environments).
app.use('/api-docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec, {
  customSiteTitle: 'ShahGrid API Docs',
  swaggerOptions: {
    persistAuthorization: true,  // keep the JWT filled in across page refreshes
  },
}));

// Expose the raw OpenAPI JSON for tooling (Postman import, code-gen, etc.)
app.get('/api-docs.json', (_req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.send(swaggerSpec);
});

// ── Security & parsing ────────────────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: env.FRONTEND_URL,
  credentials: true,
}));
app.use(cookieParser());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ── Logging ───────────────────────────────────────────────────────────────────
app.use(
  morgan('combined', {
    stream: { write: (msg) => logger.http(msg.trim()) },
    skip: () => env.NODE_ENV === 'test',
  })
);

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Secondary, in-app safety net. The primary edge limit (500 req/min/IP) is
// enforced by Caddy (caddy-ratelimit). Keep this window/limit looser than the
// edge so Caddy is always the gate that trips first under normal load.
app.use(
  rateLimit({
    windowMs: 60 * 1000,
    max: 1000,
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: { code: 'RATE_LIMITED', message: 'Too many requests' } },
  })
);

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ status: 'ok', timestamp: new Date().toISOString() }));

// ── Routes ────────────────────────────────────────────────────────────────────
const api = env.API_PREFIX;

app.use(`${api}/auth`, authRoutes);
app.use(`${api}/users`, usersRoutes);
app.use(`${api}/retailers`, retailersRoutes);
app.use(`${api}/products`, productsRoutes);
app.use(`${api}/orders`, ordersRoutes);
app.use(`${api}/orders`, challansRoutes);
app.use(`${api}/shipments`, shipmentsRoutes);
app.use(`${api}/payments`, paymentsRoutes);
app.use(`${api}/returns`, returnsRoutes);
app.use(`${api}/visits`, visitsRoutes);
app.use(`${api}/checkins`, checkInsRoutes);
app.use(`${api}/analytics`, analyticsRoutes);
app.use(`${api}/settings`, settingsRoutes);
app.use(`${api}/direct-sales`, directSalesRoutes);

// ── 404 ───────────────────────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Route not found' } });
});

// ── Global error handler ──────────────────────────────────────────────────────
app.use(errorHandler);

export default app;
