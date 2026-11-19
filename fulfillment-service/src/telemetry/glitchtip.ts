import * as Sentry from '@sentry/nestjs';

const service = process.env.OTEL_SERVICE_NAME ?? 'fulfillment-service';

Sentry.init({
  dsn: process.env.SENTRY_DSN || undefined,
  environment: process.env.APP_ENV ?? process.env.NODE_ENV ?? 'development',
  release: process.env.APP_RELEASE ?? 'unknown',
  maxBreadcrumbs: 0,
  tracesSampleRate: 0,
  beforeSend(event) {
    event.request = undefined;
    event.user = undefined;
    event.contexts = undefined;
    event.extra = undefined;
    event.breadcrumbs = [];
    event.message = undefined;
    event.transaction = undefined;
    event.tags = { service, environment: event.environment ?? 'unknown' };
    for (const exception of event.exception?.values ?? []) {
      exception.value = '[redacted]';
      if (exception.mechanism) delete exception.mechanism.data;
    }
    return event;
  },
});
