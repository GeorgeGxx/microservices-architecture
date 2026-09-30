import { describe, expect, it } from 'vitest';
import { canCancelOrder } from './orderPipeline';

describe('order cancellation policy', () => {
  it('allows cancellation only while the backend status is PLACED', () => {
    expect(canCancelOrder('PLACED')).toBe(true);
    expect(canCancelOrder(' placed ')).toBe(true);
  });

  it.each(['SHIPPED', 'DELIVERED', 'CANCELLED', 'CONFIRMED', 'PREPARING', 'UNKNOWN', null, undefined])(
    'does not allow cancellation for status %s',
    (status) => expect(canCancelOrder(status)).toBe(false)
  );
});
