import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { FulfillmentMetricsService } from './fulfillment-metrics.service';

@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  constructor(private readonly metricsService: FulfillmentMetricsService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<any> {
    const http = context.switchToHttp();
    const req = http.getRequest();
    const res = http.getResponse();
    const start = process.hrtime();

    return next.handle().pipe(
      tap({
        next: () => {
          this.recordMetric(req, res, start);
        },
        error: () => {
          this.recordMetric(req, res, start);
        },
      }),
    );
  }

  private recordMetric(req: any, res: any, start: [number, number]) {
    const diff = process.hrtime(start);
    const durationSeconds = diff[0] + diff[1] / 1e9;
    const path = req.route?.path || req.url || 'unknown';
    const status = String(res.statusCode || 200);
    const method = req.method || 'GET';

    this.metricsService.httpRequests.observe(
      {
        service: 'fulfillment-service',
        status,
        uri: path,
        method,
      },
      durationSeconds,
    );
  }
}
