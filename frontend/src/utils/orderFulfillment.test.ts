import { describe, expect, it } from 'vitest';
import { getOrderFulfillmentStageIndex, getOrderStatusPresentation, ORDER_FULFILLMENT_STAGES } from './orderFulfillment';

describe('order fulfillment view model', () => {
  it('maps only the persisted order-service shipment states to progress steps', () => {
    expect(ORDER_FULFILLMENT_STAGES.map((stage) => stage.status)).toEqual(['PLACED', 'SHIPPED', 'DELIVERED']);
    expect(ORDER_FULFILLMENT_STAGES.map((stage) => stage.title)).toEqual(['Order placed', 'In transit', 'Delivered']);
    expect(getOrderFulfillmentStageIndex('PLACED')).toBe(0);
    expect(getOrderFulfillmentStageIndex('shipped')).toBe(1);
    expect(getOrderFulfillmentStageIndex('DELIVERED')).toBe(2);
  });

  it('uses consistent storefront and operations labels for persisted enum values', () => {
    expect(getOrderStatusPresentation('PLACED').label).toBe('Placed');
    expect(getOrderStatusPresentation('SHIPPED').label).toBe('In Transit');
    expect(getOrderStatusPresentation('DELIVERED').label).toBe('Delivered');
    expect(getOrderStatusPresentation('CANCELLED').label).toBe('Cancelled');
  });

  it('does not fabricate progress for cancelled or unsupported statuses', () => {
    expect(getOrderFulfillmentStageIndex('CANCELLED')).toBe(-1);
    expect(getOrderFulfillmentStageIndex('PREPARING')).toBe(-1);
    expect(getOrderFulfillmentStageIndex(null)).toBe(-1);
  });
});
