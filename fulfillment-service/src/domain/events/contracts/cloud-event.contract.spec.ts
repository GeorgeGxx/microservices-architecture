import { parseCloudEvent } from './cloud-event.contract';

describe('parseCloudEvent', () => {
  it('should handle null, undefined, or primitive values safely', () => {
    expect(parseCloudEvent(null)).toEqual({ eventType: 'UNKNOWN', data: {} });
    expect(parseCloudEvent(undefined)).toEqual({ eventType: 'UNKNOWN', data: {} });
    expect(parseCloudEvent('string-payload')).toEqual({ eventType: 'UNKNOWN', data: {} });
    expect(parseCloudEvent(12345)).toEqual({ eventType: 'UNKNOWN', data: {} });
  });

  it('should unpack valid CloudEvents 1.0 envelope', () => {
    const cloudEvent = {
      specversion: '1.0',
      id: 'ce-uuid-1',
      source: '/orders-service',
      type: 'com.microservices.orders.order.placed.v1',
      data: {
        orderNumber: 'ORD-999',
        orderStatus: 'PLACED',
      },
    };

    const result = parseCloudEvent<{ orderNumber: string; orderStatus: string }>(cloudEvent);
    expect(result.id).toBe('ce-uuid-1');
    expect(result.eventType).toBe('com.microservices.orders.order.placed.v1');
    expect(result.data.orderNumber).toBe('ORD-999');
    expect(result.data.orderStatus).toBe('PLACED');
  });

  it('should fallback to UNKNOWN for CloudEvent without type', () => {
    const cloudEvent = {
      specversion: '1.0',
      data: { key: 'value' },
    };

    const result = parseCloudEvent(cloudEvent);
    expect(result.eventType).toBe('UNKNOWN');
    expect(result.data).toEqual({ key: 'value' });
    expect(result.id).toBeUndefined();
  });

  it('should unpack flat schema with eventType', () => {
    const flat = {
      id: 'flat-id-1',
      eventType: 'SHIPMENT_DISPATCHED',
      orderNumber: 'ORD-123',
    };

    const result = parseCloudEvent(flat);
    expect(result.id).toBe('flat-id-1');
    expect(result.eventType).toBe('SHIPMENT_DISPATCHED');
    expect(result.data).toEqual(flat);
  });

  it('should unpack flat schema with event_type', () => {
    const flat = {
      event_type: 'PAYMENT_COMPLETED',
      order_number: 'ORD-456',
    };

    const result = parseCloudEvent(flat);
    expect(result.eventType).toBe('PAYMENT_COMPLETED');
    expect(result.data).toEqual(flat);
  });

  it('should unpack flat schema with orderStatus or status', () => {
    const flatOrder = {
      orderNumber: 'ORD-789',
      orderStatus: 'CANCELLED',
    };
    expect(parseCloudEvent(flatOrder).eventType).toBe('CANCELLED');

    const flatPayment = {
      orderNumber: 'ORD-789',
      status: 'FAILED',
    };
    expect(parseCloudEvent(flatPayment).eventType).toBe('FAILED');
  });

  it('should default to UNKNOWN if no status or event type is present in flat schema', () => {
    const emptyFlat = { orderNumber: 'ORD-000' };
    expect(parseCloudEvent(emptyFlat).eventType).toBe('UNKNOWN');
  });
});
