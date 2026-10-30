import { FulfillmentMetricsService } from './fulfillment-metrics.service';

describe('FulfillmentMetricsService', () => {
  let service: FulfillmentMetricsService;

  beforeEach(() => {
    service = new FulfillmentMetricsService();
  });

  it('should initialize counters and return metrics string', async () => {
    expect(service.shipmentsTotal).toBeDefined();
    expect(service.dispatchedTotal).toBeDefined();
    expect(service.deliveredTotal).toBeDefined();

    service.shipmentsTotal.inc({ status: 'AWAITING_PICKUP', carrier: 'DHL Express' });
    service.dispatchedTotal.inc();
    service.deliveredTotal.inc();

    const metrics = await service.getMetrics();
    expect(metrics).toContain('ecommerce_shipments_total');
    expect(metrics).toContain('ecommerce_shipments_dispatched_total');
    expect(metrics).toContain('ecommerce_shipments_delivered_total');
  });
});
