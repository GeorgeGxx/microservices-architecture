import { jest } from '@jest/globals';
import { KafkaEventPublisher } from './kafka-event.publisher';
import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentDeliveredEvent } from '../../domain/events/shipment-delivered.event';

describe('KafkaEventPublisher', () => {
  let publisher: KafkaEventPublisher;
  let mockProducer: any;

  beforeEach(() => {
    publisher = new KafkaEventPublisher();
    mockProducer = {
      connect: jest.fn().mockResolvedValue(undefined),
      disconnect: jest.fn().mockResolvedValue(undefined),
      send: jest.fn().mockResolvedValue(undefined),
    };
    (publisher as any).producer = mockProducer;
  });

  it('should connect and disconnect on module lifecycle', async () => {
    await publisher.onModuleInit();
    expect(mockProducer.connect).toHaveBeenCalled();

    await publisher.onModuleDestroy();
    expect(mockProducer.disconnect).toHaveBeenCalled();
  });

  it('should publish dispatched event', async () => {
    const event = new ShipmentDispatchedEvent('shp-1', 'ORD-1', 'DHL Express', 'DHL-12345678', new Date());
    await publisher.publishDispatched(event);
    expect(mockProducer.send).toHaveBeenCalledWith(
      expect.objectContaining({
        topic: expect.any(String),
        messages: expect.arrayContaining([
          expect.objectContaining({ key: 'ORD-1' }),
        ]),
      }),
    );
  });

  it('should publish delivered event', async () => {
    const event = new ShipmentDeliveredEvent('shp-2', 'ORD-2', 'DHL Express', 'DHL-87654321', new Date());
    await publisher.publishDelivered(event);
    expect(mockProducer.send).toHaveBeenCalledWith(
      expect.objectContaining({
        topic: expect.any(String),
        messages: expect.arrayContaining([
          expect.objectContaining({ key: 'ORD-2' }),
        ]),
      }),
    );
  });

  it('should publish failed event for Saga backward compensation', async () => {
    await publisher.publishFailed('ORD-3', 'Invalid address');
    expect(mockProducer.send).toHaveBeenCalledWith(
      expect.objectContaining({
        topic: expect.any(String),
        messages: expect.arrayContaining([
          expect.objectContaining({ key: 'ORD-3' }),
        ]),
      }),
    );
  });

  it('should propagate outbox persistence failure instead of sending uncommitted events to Kafka', async () => {
    const failingOutboxRepo: any = {
      create: jest.fn((x) => x),
      save: jest.fn().mockRejectedValue(new Error('DB connection lost')),
    };
    const outboxPublisher = new KafkaEventPublisher(failingOutboxRepo);
    (outboxPublisher as any).producer = mockProducer;

    await expect(outboxPublisher.publishFailed('ORD-DB-ERR', 'Reason')).rejects.toThrow('DB connection lost');
    expect(mockProducer.send).not.toHaveBeenCalled();
  });

  it('should rethrow when publishDlq fails so consumer does not commit offsets', async () => {
    mockProducer.send.mockRejectedValueOnce(new Error('DLQ broker unavailable'));
    await expect(publisher.publishDlq('payments-topic', { orderNumber: 'ORD-9' }, 'parse error')).rejects.toThrow(
      'DLQ broker unavailable',
    );
  });

  it('should flush pending outbox events via transactional lock and fallback find', async () => {
    const outboxEvent = {
      id: 'outbox-1',
      aggregateId: 'ORD-OUTBOX-1',
      eventType: 'SHIPMENT_DISPATCHED',
      payload: '{"orderNumber":"ORD-OUTBOX-1"}',
      status: 'PENDING',
      retryCount: 0,
    };

    // 1. Transactional manager path
    const mockQb: any = {
      setLock: jest.fn().mockReturnThis(),
      setOnLocked: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      take: jest.fn().mockReturnThis(),
      getMany: jest.fn().mockResolvedValue([{ ...outboxEvent }]),
    };
    const mockEm: any = {
      createQueryBuilder: jest.fn().mockReturnValue(mockQb),
      save: jest.fn().mockResolvedValue(undefined),
    };
    const txOutboxRepo: any = {
      manager: {
        transaction: jest.fn(async (cb: any) => cb(mockEm)),
      },
      save: jest.fn().mockResolvedValue(undefined),
    };

    const txPublisher = new KafkaEventPublisher(txOutboxRepo);
    (txPublisher as any).producer = mockProducer;
    await txPublisher.flushPendingOutbox();

    expect(mockProducer.send).toHaveBeenCalled();
    expect(txOutboxRepo.save).toHaveBeenCalledWith(expect.objectContaining({ status: 'PUBLISHED' }));

    // 2. Fallback find path + retry failure
    const fallbackRepo: any = {
      find: jest.fn().mockResolvedValue([{ ...outboxEvent, retryCount: 4 }]),
      save: jest.fn().mockResolvedValue(undefined),
    };
    mockProducer.send.mockRejectedValueOnce(new Error('Kafka broker down'));
    const fallbackPublisher = new KafkaEventPublisher(fallbackRepo);
    (fallbackPublisher as any).producer = mockProducer;
    await fallbackPublisher.flushPendingOutbox();

    expect(fallbackRepo.save).toHaveBeenCalledWith(expect.objectContaining({ status: 'FAILED', retryCount: 5 }));
  });
});
