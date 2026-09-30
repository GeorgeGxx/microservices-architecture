import { describe, expect, it } from 'vitest';
import { getOrderFulfillmentStageIndex, ORDER_FULFILLMENT_STAGES } from './orderFulfillment';

describe('order fulfillment view model', () => {
  it('maps only the persisted order-service shipment states to progress steps', () => {
    expect(ORDER_FULFILLMENT_STAGES.map((stage) => stage.status)).toEqual(['PLACED', 'SHIPPED', 'DELIVERED']);
    expect(getOrderFulfillmentStageIndex('PLACED')).toBe(0);
    expect(getOrderFulfillmentStageIndex('shipped')).toBe(1);
    expect(getOrderFulfillmentStageIndex('DELIVERED')).toBe(2);
  });

  it('does not fabricate progress for cancelled or unsupported statuses', () => {
    expect(getOrderFulfillmentStageIndex('CANCELLED')).toBe(-1);
    expect(getOrderFulfillmentStageIndex('PREPARING')).toBe(-1);
    expect(getOrderFulfillmentStageIndex(null)).toBe(-1);
  });
});
