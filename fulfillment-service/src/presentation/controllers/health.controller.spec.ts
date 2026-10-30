import { Test, TestingModule } from '@nestjs/testing';
import { HealthController } from './health.controller';
import { FulfillmentMetricsService } from '../../infrastructure/metrics/fulfillment-metrics.service';

describe('HealthController', () => {
  let controller: HealthController;
  let metricsService: Partial<FulfillmentMetricsService>;

  beforeEach(async () => {
    metricsService = {
      getMetrics: jest.fn().mockResolvedValue('# HELP ecommerce_shipments_total ...'),
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [HealthController],
      providers: [
        { provide: FulfillmentMetricsService, useValue: metricsService },
      ],
    }).compile();

    controller = module.get<HealthController>(HealthController);
  });

  it('should return health status UP', () => {
    const health = controller.getHealth();
    expect(health.status).toBe('UP');
    expect(health.service).toBe('fulfillment-service');
  });

  it('should return actuator health matching getHealth', () => {
    const health = controller.getActuatorHealth();
    expect(health.status).toBe('UP');
  });

  it('should return prometheus metrics', async () => {
    const mockRes = {
      set: jest.fn(),
      end: jest.fn(),
    } as any;

    await controller.getMetrics(mockRes);
    expect(metricsService.getMetrics).toHaveBeenCalled();
    expect(mockRes.set).toHaveBeenCalledWith('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    expect(mockRes.end).toHaveBeenCalled();
  });
});
