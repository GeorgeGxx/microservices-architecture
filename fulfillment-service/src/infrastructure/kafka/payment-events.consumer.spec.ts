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
});
