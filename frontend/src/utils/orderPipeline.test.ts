import { describe, it, expect } from 'vitest';
import {
  canCancelOrder,
  getNextDeliveryStage,
  getDeliveryStageIndex,
  computeEffectiveStatus,
  DELIVERY_STAGES,
} from './orderPipeline';

describe('Order Delivery Pipeline & Cancellation Policy (TDD)', () => {
  it('should allow cancellation strictly during PLACED stage', () => {
    expect(canCancelOrder('PLACED')).toBe(true);
    expect(canCancelOrder('placed')).toBe(true);
  });

  it('should NOT allow cancellation once CONFIRMED (Angular 21 parity)', () => {
    expect(canCancelOrder('CONFIRMED')).toBe(false);
    expect(canCancelOrder('confirmed')).toBe(false);
  });

  it('should NOT allow cancellation for downstream stages (PREPARING, SHIPPED, DELIVERED, CANCELLED)', () => {
    expect(canCancelOrder('PREPARING')).toBe(false);
    expect(canCancelOrder('SHIPPED')).toBe(false);
    expect(canCancelOrder('DELIVERED')).toBe(false);
    expect(canCancelOrder('CANCELLED')).toBe(false);
    expect(canCancelOrder('UNKNOWN')).toBe(false);
  });

  it('should step through all 5 delivery stages with descriptive notifications', () => {
    const s1 = getNextDeliveryStage('PLACED');
    expect(s1?.nextStatus).toBe('CONFIRMED');
    expect(s1?.milestoneTitle).toContain('Confirmed');

    const s2 = getNextDeliveryStage('CONFIRMED');
    expect(s2?.nextStatus).toBe('PREPARING');
    expect(s2?.milestoneTitle).toContain('Warehouse');

    const s3 = getNextDeliveryStage('PREPARING');
    expect(s3?.nextStatus).toBe('SHIPPED');
    expect(s3?.milestoneTitle).toContain('In Transit');

    const s4 = getNextDeliveryStage('SHIPPED');
    expect(s4?.nextStatus).toBe('DELIVERED');
    expect(s4?.milestoneTitle).toContain('Delivered');

    const s5 = getNextDeliveryStage('DELIVERED');
    expect(s5).toBeNull();

    const sCancelled = getNextDeliveryStage('CANCELLED');
    expect(sCancelled).toBeNull();
  });

  it('should strictly halt and freeze in CANCELLED status without continuing transit', () => {
    expect(computeEffectiveStatus('CANCELLED', 'DELIVERED')).toBe('CANCELLED');
    expect(computeEffectiveStatus('PLACED', 'CANCELLED')).toBe('CANCELLED');
    expect(computeEffectiveStatus('CONFIRMED', 'CANCELLED')).toBe('CANCELLED');
    expect(computeEffectiveStatus('CANCELLED', null)).toBe('CANCELLED');
  });

  it('should allow progressive transit for non-cancelled orders to DELIVERED', () => {
    expect(computeEffectiveStatus('PLACED', 'CONFIRMED')).toBe('CONFIRMED');
    expect(computeEffectiveStatus('PLACED', 'PREPARING')).toBe('PREPARING');
    expect(computeEffectiveStatus('PLACED', 'SHIPPED')).toBe('SHIPPED');
    expect(computeEffectiveStatus('PLACED', 'DELIVERED')).toBe('DELIVERED');
  });

  it('should accurately index delivery stages for stepper tracking', () => {
    expect(getDeliveryStageIndex('PLACED')).toBe(0);
    expect(getDeliveryStageIndex('CONFIRMED')).toBe(1);
    expect(getDeliveryStageIndex('PREPARING')).toBe(2);
    expect(getDeliveryStageIndex('SHIPPED')).toBe(3);
    expect(getDeliveryStageIndex('DELIVERED')).toBe(4);
    expect(getDeliveryStageIndex('CANCELLED')).toBe(-1);
    expect(DELIVERY_STAGES).toHaveLength(5);
  });
});
