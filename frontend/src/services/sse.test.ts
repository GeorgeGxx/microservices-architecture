import { describe, expect, it } from 'vitest';
import { createOrderNotification, parseOrderStatusEvent } from './sse';

describe('order status SSE contract', () => {
  it.each(['PLACED', 'SHIPPED', 'DELIVERED', 'CANCELLED'] as const)(
    'accepts persisted status %s from Orders Service',
    (orderStatus) => {
      expect(parseOrderStatusEvent(JSON.stringify({ orderNumber: 'ORD-42', orderStatus }))).toEqual({
        orderNumber: 'ORD-42',
        orderStatus,
      });
    }
  );

  it('normalizes status casing and ignores malformed or unsupported events', () => {
    expect(parseOrderStatusEvent('{"orderNumber":"ORD-42","orderStatus":"shipped"}')?.orderStatus).toBe('SHIPPED');
    expect(parseOrderStatusEvent('{broken')).toBeNull();
    expect(parseOrderStatusEvent('{"orderNumber":"ORD-42","orderStatus":"PREPARING"}')).toBeNull();
    expect(parseOrderStatusEvent('{"orderStatus":"DELIVERED"}')).toBeNull();
  });

  it('turns the persisted status into a concise, stable live notification', () => {
    const event = { orderNumber: 'ORD-42', orderStatus: 'SHIPPED' as const, userId: 'customer-1' };
    const notification = createOrderNotification(event);
    expect(notification).toMatchObject({
      id: 'order-ORD-42-SHIPPED',
      title: 'Order in transit',
      message: 'Order #ORD-42 is now in transit.',
      type: 'order',
      userId: 'customer-1',
    });
  });
});
