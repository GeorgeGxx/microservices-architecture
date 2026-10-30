import { Test, TestingModule } from '@nestjs/testing';
import { ShipmentsController } from './shipments.controller';
import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from '../../application/use-cases/dispatch-shipment.use-case';
import { DeliverShipmentUseCase } from '../../application/use-cases/deliver-shipment.use-case';
import { GetShipmentUseCase } from '../../application/use-cases/get-shipment.use-case';
import { FulfillmentMetricsService } from '../../infrastructure/metrics/fulfillment-metrics.service';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';

describe('ShipmentsController', () => {
  let controller: ShipmentsController;
  let createUseCase: Partial<CreateShipmentUseCase>;
  let dispatchUseCase: Partial<DispatchShipmentUseCase>;
  let deliverUseCase: Partial<DeliverShipmentUseCase>;
  let getUseCase: Partial<GetShipmentUseCase>;
  let metricsService: Partial<FulfillmentMetricsService>;

  const mockShipmentResponse = {
    id: 'test-uuid-1234',
    orderNumber: 'ORD-CTRL-01',
    status: ShipmentStatus.AWAITING_PICKUP,
    carrier: 'DHL Express',
    trackingNumber: 'DHL-ABC12345',
    recipientName: 'Pam Beesly',
    deliveryAddress: 'Main St 10, Scranton 18503',
    trackingEvents: [],
    createdAt: new Date(),
  };

  beforeEach(async () => {
    createUseCase = {
      execute: jest.fn().mockResolvedValue(mockShipmentResponse),
    };
    dispatchUseCase = {
      execute: jest.fn().mockResolvedValue({ ...mockShipmentResponse, status: ShipmentStatus.DISPATCHED }),
    };
    deliverUseCase = {
      execute: jest.fn().mockResolvedValue({ ...mockShipmentResponse, status: ShipmentStatus.DELIVERED }),
    };
    getUseCase = {
      executeByOrderNumber: jest.fn().mockResolvedValue(mockShipmentResponse),
      executeByTrackingNumber: jest.fn().mockResolvedValue(mockShipmentResponse),
    };
    metricsService = {
      shipmentsTotal: { inc: jest.fn() } as any,
      dispatchedTotal: { inc: jest.fn() } as any,
      deliveredTotal: { inc: jest.fn() } as any,
    };

    const module: TestingModule = await Test.createTestingModule({
      controllers: [ShipmentsController],
      providers: [
        { provide: CreateShipmentUseCase, useValue: createUseCase },
        { provide: DispatchShipmentUseCase, useValue: dispatchUseCase },
        { provide: DeliverShipmentUseCase, useValue: deliverUseCase },
        { provide: GetShipmentUseCase, useValue: getUseCase },
        { provide: FulfillmentMetricsService, useValue: metricsService },
      ],
    }).compile();

    controller = module.get<ShipmentsController>(ShipmentsController);
  });

  it('should create shipment via POST /api/v1/shipments', async () => {
    const res = await controller.createShipment({
      orderNumber: 'ORD-CTRL-01',
      recipientName: 'Pam Beesly',
      street: 'Main St 10',
      city: 'Scranton',
      postalCode: '18503',
    });

    expect(res.orderNumber).toBe('ORD-CTRL-01');
    expect(createUseCase.execute).toHaveBeenCalled();
    expect(metricsService.shipmentsTotal.inc).toHaveBeenCalled();
  });

  it('should dispatch shipment via PATCH /order/:orderNumber/dispatch', async () => {
    const res = await controller.dispatchShipment('ORD-CTRL-01', { location: 'Local Hub' });
    expect(res.status).toBe(ShipmentStatus.DISPATCHED);
    expect(dispatchUseCase.execute).toHaveBeenCalledWith('ORD-CTRL-01', 'Local Hub');
    expect(metricsService.dispatchedTotal.inc).toHaveBeenCalled();
  });

  it('should deliver shipment via PATCH /order/:orderNumber/deliver', async () => {
    const res = await controller.deliverShipment('ORD-CTRL-01', { location: 'Front Desk' });
    expect(res.status).toBe(ShipmentStatus.DELIVERED);
    expect(deliverUseCase.execute).toHaveBeenCalledWith('ORD-CTRL-01', 'Front Desk');
    expect(metricsService.deliveredTotal.inc).toHaveBeenCalled();
  });

  it('should get shipment by order and tracking numbers', async () => {
    const byOrder = await controller.getByOrderNumber('ORD-CTRL-01');
    expect(byOrder.orderNumber).toBe('ORD-CTRL-01');

    const byTracking = await controller.getByTrackingNumber('DHL-ABC12345');
    expect(byTracking.trackingNumber).toBe('DHL-ABC12345');
  });
});
