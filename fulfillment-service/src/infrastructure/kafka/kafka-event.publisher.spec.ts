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
});
