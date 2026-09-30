import { describe, expect, it } from 'vitest';
import { parseOrderStatusEvent } from './sse';

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
});
