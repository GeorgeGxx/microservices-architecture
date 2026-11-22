export interface SanitizedEvent {
  request?: unknown;
  user?: unknown;
  contexts?: unknown;
  extra?: unknown;
  breadcrumbs?: unknown[];
  message?: string;
  transaction?: string;
  environment?: string;
  tags?: Record<string, string | number | boolean | null | undefined>;
  exception?: {
    values?: Array<{
      value?: string;
      mechanism?: { data?: unknown; [key: string]: unknown };
    }>;
  };
}

export function sanitizeGlitchTipEvent<T extends object>(event: T, service: string): T {
  const sanitizedEvent = event as T & SanitizedEvent;
  sanitizedEvent.request = undefined;
  sanitizedEvent.user = undefined;
  sanitizedEvent.contexts = undefined;
  sanitizedEvent.extra = undefined;
  sanitizedEvent.breadcrumbs = [];
  sanitizedEvent.message = undefined;
  sanitizedEvent.transaction = undefined;
  sanitizedEvent.tags = { service, environment: sanitizedEvent.environment ?? 'unknown' };

  for (const exception of sanitizedEvent.exception?.values ?? []) {
    exception.value = '[redacted]';
    if (exception.mechanism) delete exception.mechanism.data;
  }

  return event;
}
