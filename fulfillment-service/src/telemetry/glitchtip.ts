import * as Sentry from '@sentry/nestjs';
import { sanitizeGlitchTipEvent } from './glitchtip-sanitizer';

const service = process.env.OTEL_SERVICE_NAME ?? 'fulfillment-service';

Sentry.init({
  dsn: process.env.SENTRY_DSN || undefined,
  environment: process.env.APP_ENV ?? process.env.NODE_ENV ?? 'development',
  release: process.env.APP_RELEASE ?? 'unknown',
  maxBreadcrumbs: 0,
  tracesSampleRate: 0,
  beforeSend: (event) => sanitizeGlitchTipEvent(event, service),
});
