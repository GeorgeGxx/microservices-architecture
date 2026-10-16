import { describe, expect, it } from 'vitest';
import { getOrderStatusNotificationCopy } from './orderNotificationCopy';

describe('getOrderStatusNotificationCopy', () => {
  it('returns appropriate copy for PLACED status', () => {
    const copy = getOrderStatusNotificationCopy('PLACED', 'ORD-101');
    expect(copy.title).toBe('Order placed');
    expect(copy.message).toBe('Order #ORD-101 was placed successfully.');
  });

  it('returns appropriate copy for SHIPPED status', () => {
    const copy = getOrderStatusNotificationCopy('SHIPPED', 'ORD-102');
    expect(copy.title).toBe('Order in transit');
    expect(copy.message).toBe('Order #ORD-102 is now in transit.');
  });

  it('returns appropriate copy for DELIVERED status', () => {
    const copy = getOrderStatusNotificationCopy('DELIVERED', 'ORD-103');
    expect(copy.title).toBe('Order delivered');
    expect(copy.message).toBe('Order #ORD-103 has been delivered.');
  });

  it('returns appropriate copy for CANCELLED status', () => {
    const copy = getOrderStatusNotificationCopy('CANCELLED', 'ORD-104');
    expect(copy.title).toBe('Order cancelled');
    expect(copy.message).toBe('Order #ORD-104 was cancelled.');
  });
});
