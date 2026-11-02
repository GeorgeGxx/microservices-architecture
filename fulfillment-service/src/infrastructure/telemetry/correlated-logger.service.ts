import { Injectable, LoggerService } from '@nestjs/common';
import { trace } from '@opentelemetry/api';

@Injectable()
export class CorrelatedLoggerService implements LoggerService {
  private formatMessage(level: string, message: any, context?: string): string {
    const span = trace.getActiveSpan();
    const traceId = span?.spanContext().traceId || '';
    const spanId = span?.spanContext().spanId || '';
    const timestamp = new Date().toISOString();
    const formattedLevel = level.toUpperCase().padStart(5);
    const ctx = context ? `[${context}] ` : '';
    const msg = typeof message === 'object' ? JSON.stringify(message) : message;

    return `${timestamp} ${formattedLevel} [fulfillment-service,${traceId},${spanId}] ${ctx}${msg}`;
  }

  log(message: any, context?: string) {
    // eslint-disable-next-line no-console
    console.log(this.formatMessage('info', message, context));
  }

  error(message: any, traceStack?: string, context?: string) {
    // eslint-disable-next-line no-console
    console.error(this.formatMessage('error', message, context));
    if (traceStack) {
      // eslint-disable-next-line no-console
      console.error(traceStack);
    }
  }

  warn(message: any, context?: string) {
    // eslint-disable-next-line no-console
    console.warn(this.formatMessage('warn', message, context));
  }

  debug(message: any, context?: string) {
    // eslint-disable-next-line no-console
    console.debug(this.formatMessage('debug', message, context));
  }

  verbose(message: any, context?: string) {
    // eslint-disable-next-line no-console
    console.info(this.formatMessage('verbose', message, context));
  }
}
