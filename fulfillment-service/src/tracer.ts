// Disable OTLP metrics exporter because fulfillment-service exposes metrics via Prometheus scraping (/metrics)
process.env.OTEL_METRICS_EXPORTER = process.env.OTEL_METRICS_EXPORTER || 'none';

import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME, ATTR_SERVICE_VERSION } from '@opentelemetry/semantic-conventions';

const otelEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4318';
const traceUrl = otelEndpoint.endsWith('/v1/traces')
  ? otelEndpoint
  : `${otelEndpoint.replace(/\/$/, '')}/v1/traces`;

const traceExporter = new OTLPTraceExporter({
  url: traceUrl,
});

export const otelSdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: 'fulfillment-service',
    [ATTR_SERVICE_VERSION]: '1.0.0',
    'deployment.environment': process.env.NODE_ENV || 'development',
  }),
  traceExporter,
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

try {
  otelSdk.start();
  // eslint-disable-next-line no-console
  console.log('[Telemetry] OpenTelemetry initialized for fulfillment-service ->', traceUrl);
} catch (error) {
  // eslint-disable-next-line no-console
  console.error('[Telemetry] Failed to initialize OpenTelemetry SDK:', error);
}

process.on('SIGTERM', () => {
  otelSdk
    .shutdown()
    // eslint-disable-next-line no-console
    .then(() => console.log('[Telemetry] OpenTelemetry SDK shut down gracefully'))
    .catch((err) => console.error('[Telemetry] Error shutting down OpenTelemetry SDK', err));
});
