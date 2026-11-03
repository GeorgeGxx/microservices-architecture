import { jest } from '@jest/globals';
import { PaymentEventsConsumer } from './payment-events.consumer';

describe('PaymentEventsConsumer', () => {
  let consumer: PaymentEventsConsumer;
  let mockUseCase: any;
  let mockKafkaConsumer: any;

  beforeEach(() => {
    mockUseCase = {
      execute: jest.fn().mockResolvedValue({}),
    };
    consumer = new PaymentEventsConsumer(mockUseCase);
    mockKafkaConsumer = {
      connect: jest.fn().mockResolvedValue(undefined),
      subscribe: jest.fn().mockResolvedValue(undefined),
      run: jest.fn().mockResolvedValue(undefined),
      disconnect: jest.fn().mockResolvedValue(undefined),
    };
    (consumer as any).consumer = mockKafkaConsumer;
  });

  it('should connect, subscribe, and register run loop on init', async () => {
    await consumer.onModuleInit();
    expect(mockKafkaConsumer.connect).toHaveBeenCalled();
    expect(mockKafkaConsumer.subscribe).toHaveBeenCalled();
    expect(mockKafkaConsumer.run).toHaveBeenCalled();
  });

  it('should disconnect on destroy', async () => {
    await consumer.onModuleDestroy();
    expect(mockKafkaConsumer.disconnect).toHaveBeenCalled();
  });

  it('should process payment event and trigger shipment creation', async () => {
    await consumer.onModuleInit();
    const runCall = mockKafkaConsumer.run.mock.calls[0][0];
    const eachMessage = runCall.eachMessage;

    const payload = {
      orderNumber: 'ORD-PAY-99',
      recipientName: 'Pam Beesly',
      street: '123 Dunder St',
      city: 'Scranton',
      postalCode: '18503',
      items: [{ sku: 'SKU-PAPER', quantity: 10 }],
    };

    await eachMessage({
      message: {
        value: Buffer.from(JSON.stringify(payload)),
      },
    });

    expect(mockUseCase.execute).toHaveBeenCalledWith(
      expect.objectContaining({
        orderNumber: 'ORD-PAY-99',
      }),
    );
  });

  it('should ignore PAYMENT_FAILED and publish SHIPMENT_FAILED when FAIL_SHIPMENT street is provided', async () => {
    const mockPublisher = { publishFailed: jest.fn().mockResolvedValue(undefined) };
    const mockDispatch = { execute: jest.fn().mockResolvedValue({}) };
    consumer = new PaymentEventsConsumer(mockUseCase, mockDispatch as any, mockPublisher as any);
    (consumer as any).consumer = mockKafkaConsumer;

    await consumer.onModuleInit();
    const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

    // 1. Ignored failed payment
    await eachMessage({
      message: {
        value: Buffer.from(JSON.stringify({ order_number: 'ORD-FAIL-1', status: 'FAILED' })),
      },
    });
    expect(mockUseCase.execute).not.toHaveBeenCalled();

    // 2. Simulated fulfillment failure -> emits SHIPMENT_FAILED
    await eachMessage({
      message: {
        value: Buffer.from(JSON.stringify({ order_number: 'ORD-FAIL-2', shipping_address: '999 FAIL_SHIPMENT Rd' })),
      },
    });
    expect(mockPublisher.publishFailed).toHaveBeenCalledWith(
      'ORD-FAIL-2',
      expect.stringContaining('Undeliverable'),
    );
  });

  it('should not auto-dispatch shipment when AUTO_DISPATCH_SHIPMENT is unset or false', async () => {
    delete process.env.AUTO_DISPATCH_SHIPMENT;
    const mockDispatch = { execute: jest.fn().mockResolvedValue({}) };
    consumer = new PaymentEventsConsumer(mockUseCase, mockDispatch as any);
    (consumer as any).consumer = mockKafkaConsumer;

    await consumer.onModuleInit();
    const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

    await eachMessage({
      message: {
        value: Buffer.from(JSON.stringify({ order_number: 'ORD-DISPATCH-OFF', shipping_address: '123 Main St' })),
      },
    });

    expect(mockUseCase.execute).toHaveBeenCalled();
    expect(mockDispatch.execute).not.toHaveBeenCalled();
  });

  it('should auto-dispatch shipment when AUTO_DISPATCH_SHIPMENT is true', async () => {
    process.env.AUTO_DISPATCH_SHIPMENT = 'true';
    try {
      const mockDispatch = { execute: jest.fn().mockResolvedValue({}) };
      consumer = new PaymentEventsConsumer(mockUseCase, mockDispatch as any);
      (consumer as any).consumer = mockKafkaConsumer;

      await consumer.onModuleInit();
      const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

      await eachMessage({
        message: {
          value: Buffer.from(JSON.stringify({ order_number: 'ORD-DISPATCH-ON', shipping_address: '123 Main St' })),
        },
      });

      expect(mockUseCase.execute).toHaveBeenCalled();
      expect(mockDispatch.execute).toHaveBeenCalledWith('ORD-DISPATCH-ON', 'Regional Fulfillment Hub');
    } finally {
      delete process.env.AUTO_DISPATCH_SHIPMENT;
    }
  });

  it('should increment shipmentsTotal and dispatchedTotal metrics when metricsService is provided', async () => {
    process.env.AUTO_DISPATCH_SHIPMENT = 'true';
    try {
      const mockCreated = { status: 'AWAITING_PICKUP', carrier: 'FedEx' };
      mockUseCase.execute = jest.fn().mockResolvedValue(mockCreated);
      const mockDispatch = { execute: jest.fn().mockResolvedValue({}) };
      const mockMetrics = {
        shipmentsTotal: { inc: jest.fn() },
        dispatchedTotal: { inc: jest.fn() },
      };
      consumer = new PaymentEventsConsumer(mockUseCase, mockDispatch as any, undefined, mockMetrics as any);
      (consumer as any).consumer = mockKafkaConsumer;

      await consumer.onModuleInit();
      const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

      await eachMessage({
        message: {
          value: Buffer.from(JSON.stringify({
            order_number: 'ORD-METRICS',
            delivery_method: 'FedEx Standard Ground (3-5 days)',
          })),
        },
      });

      expect(mockMetrics.shipmentsTotal.inc).toHaveBeenCalledWith({ status: 'AWAITING_PICKUP', carrier: 'FedEx' });
      expect(mockMetrics.dispatchedTotal.inc).toHaveBeenCalled();
    } finally {
      delete process.env.AUTO_DISPATCH_SHIPMENT;
    }
  });

  it('should handle ORDER_CANCELLED event and transition shipment to CANCELLED in repository', async () => {
    const mockShipment = {
      orderNumber: 'ORD-CANCEL-1',
      status: 'AWAITING_PICKUP',
      carrier: 'DHL Express',
    };
    const mockRepo = {
      findOne: jest.fn().mockResolvedValue(mockShipment),
      save: jest.fn().mockResolvedValue(mockShipment),
    };
    const mockMetrics = {
      refreshFromDatabase: jest.fn().mockResolvedValue(undefined),
    };

    consumer = new PaymentEventsConsumer(mockUseCase, undefined, undefined, mockMetrics as any, mockRepo as any);
    (consumer as any).consumer = mockKafkaConsumer;

    await consumer.onModuleInit();
    const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

    await eachMessage({
      topic: 'orders-topic',
      message: {
        value: Buffer.from(JSON.stringify({
          orderNumber: 'ORD-CANCEL-1',
          orderStatus: 'CANCELLED',
        })),
      },
    });

    expect(mockRepo.findOne).toHaveBeenCalledWith({ where: { orderNumber: 'ORD-CANCEL-1' } });
    expect(mockShipment.status).toBe('CANCELLED');
    expect(mockRepo.save).toHaveBeenCalledWith(mockShipment);
    expect(mockMetrics.refreshFromDatabase).toHaveBeenCalled();
  });

  it('should handle ORDER_SHIPPED and ORDER_DELIVERED events from orders-topic', async () => {
    const mockShipment = {
      orderNumber: 'ORD-LIFECYCLE-1',
      status: 'AWAITING_PICKUP',
      dispatchedAt: null,
      deliveredAt: null,
    };
    const mockRepo = {
      findOne: jest.fn().mockResolvedValue(mockShipment),
      save: jest.fn().mockResolvedValue(mockShipment),
    };
    const mockMetrics = {
      refreshFromDatabase: jest.fn().mockResolvedValue(undefined),
    };

    consumer = new PaymentEventsConsumer(mockUseCase, undefined, undefined, mockMetrics as any, mockRepo as any);
    (consumer as any).consumer = mockKafkaConsumer;

    await consumer.onModuleInit();
    const eachMessage = mockKafkaConsumer.run.mock.calls[0][0].eachMessage;

    // 1. Shipped
    await eachMessage({
      topic: 'orders-topic',
      message: {
        value: Buffer.from(JSON.stringify({
          orderNumber: 'ORD-LIFECYCLE-1',
          orderStatus: 'SHIPPED',
        })),
      },
    });
    expect(mockShipment.status).toBe('DISPATCHED');
    expect(mockShipment.dispatchedAt).toBeDefined();

    // 2. Delivered
    await eachMessage({
      topic: 'orders-topic',
      message: {
        value: Buffer.from(JSON.stringify({
          orderNumber: 'ORD-LIFECYCLE-1',
          orderStatus: 'DELIVERED',
        })),
      },
    });
    expect(mockShipment.status).toBe('DELIVERED');
    expect(mockShipment.deliveredAt).toBeDefined();
    expect(mockMetrics.refreshFromDatabase).toHaveBeenCalledTimes(2);
  });
});
