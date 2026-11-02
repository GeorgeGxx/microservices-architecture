import { FulfillmentMetricsService } from './fulfillment-metrics.service';
import { Repository } from 'typeorm';
import { ShipmentOrmEntity } from '../persistence/entities/shipment.orm-entity';

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

  it('should seed metrics from repository on onModuleInit', async () => {
    const qbMock = {
      select: jest.fn().mockReturnThis(),
      addSelect: jest.fn().mockReturnThis(),
      groupBy: jest.fn().mockReturnThis(),
      addGroupBy: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      getRawMany: jest.fn().mockResolvedValue([
        { carrier: 'DHL Express', status: 'AWAITING_PICKUP', count: '5' },
        { carrier: 'FedEx', status: 'DELIVERED', count: '2' },
      ]),
      getCount: jest.fn().mockResolvedValueOnce(3).mockResolvedValueOnce(2),
    };

    const mockRepo = {
      createQueryBuilder: jest.fn().mockReturnValue(qbMock),
    } as unknown as Repository<ShipmentOrmEntity>;

    const seededService = new FulfillmentMetricsService(mockRepo);
    await seededService.onModuleInit();

    const metrics = await seededService.getMetrics();
    expect(metrics).toContain('ecommerce_shipments_total{status="AWAITING_PICKUP",carrier="DHL Express"} 5');
    expect(metrics).toContain('ecommerce_shipments_total{status="DELIVERED",carrier="FedEx"} 2');
    expect(metrics).toContain('ecommerce_shipments_dispatched_total 3');
    expect(metrics).toContain('ecommerce_shipments_delivered_total 2');
  });
});
