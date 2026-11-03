import { jest } from '@jest/globals';
import { of, throwError } from 'rxjs';
import { ExecutionContext, CallHandler } from '@nestjs/common';
import { MetricsInterceptor } from './metrics.interceptor';
import { FulfillmentMetricsService } from './fulfillment-metrics.service';

describe('MetricsInterceptor', () => {
  let interceptor: MetricsInterceptor;
  let metricsServiceMock: Partial<FulfillmentMetricsService>;
  let observeMock: jest.Mock;

  beforeEach(() => {
    observeMock = jest.fn();
    metricsServiceMock = {
      httpRequests: {
        observe: observeMock,
      } as any,
    };
    interceptor = new MetricsInterceptor(metricsServiceMock as FulfillmentMetricsService);
  });

  const createMockContext = (method = 'GET', url = '/api/v1/shipments/track/DHL-1', statusCode = 200, routePath = '/api/v1/shipments/track/:trackingNumber'): ExecutionContext => {
    const req = {
      method,
      url,
      route: { path: routePath },
    };
    const res = {
      statusCode,
    };
    return {
      switchToHttp: () => ({
        getRequest: () => req,
        getResponse: () => res,
      }),
    } as unknown as ExecutionContext;
  };

  it('records http request metric on successful execution', (done) => {
    const context = createMockContext('GET', '/api/v1/shipments/track/DHL-1', 200);
    const handler: CallHandler = {
      handle: () => of({ success: true }),
    };

    interceptor.intercept(context, handler).subscribe({
      next: () => {
        expect(observeMock).toHaveBeenCalledTimes(1);
        expect(observeMock).toHaveBeenCalledWith(
          expect.objectContaining({
            service: 'fulfillment-service',
            status: '200',
            uri: '/api/v1/shipments/track/:trackingNumber',
            method: 'GET',
          }),
          expect.any(Number),
        );
        done();
      },
    });
  });

  it('records http request metric when handler throws error', (done) => {
    const context = createMockContext('POST', '/api/v1/shipments', 500, '/api/v1/shipments');
    const handler: CallHandler = {
      handle: () => throwError(() => new Error('Internal Server Error')),
    };

    interceptor.intercept(context, handler).subscribe({
      error: () => {
        expect(observeMock).toHaveBeenCalledTimes(1);
        expect(observeMock).toHaveBeenCalledWith(
          expect.objectContaining({
            service: 'fulfillment-service',
            status: '500',
            uri: '/api/v1/shipments',
            method: 'POST',
          }),
          expect.any(Number),
        );
        done();
      },
    });
  });
});
