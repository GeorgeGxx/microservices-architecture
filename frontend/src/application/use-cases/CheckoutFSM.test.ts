import { describe, expect, it, beforeEach } from 'vitest';
import { CheckoutStateMachine, CheckoutContextData } from './CheckoutFSM';

describe('CheckoutStateMachine', () => {
  let fsm: CheckoutStateMachine;
  const validData: CheckoutContextData = {
    customerName: 'Alex Mercer',
    customerEmail: 'alex@enterprise.dev',
    shippingAddress: '123 Tech Street, Suite 400',
    city: 'San Francisco',
    postalCode: '94105',
    phone: '+1 555 0199',
    deliveryMethod: 'DHL Express',
    paymentMethod: 'SIMULATED_APPROVED',
  };

  beforeEach(() => {
    fsm = new CheckoutStateMachine();
  });

  it('initializes in CUSTOMER_INFO step with null error', () => {
    expect(fsm.step).toBe('CUSTOMER_INFO');
    expect(fsm.errorMessage).toBeNull();
  });

  describe('CUSTOMER_INFO -> DELIVERY_TIER transition', () => {
    it('allows transition with valid customer details', () => {
      const success = fsm.transition('DELIVERY_TIER', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('DELIVERY_TIER');
      expect(fsm.errorMessage).toBeNull();
    });

    it('rejects transition if customer name is empty', () => {
      const success = fsm.transition('DELIVERY_TIER', { ...validData, customerName: '   ' });
      expect(success).toBe(false);
      expect(fsm.step).toBe('CUSTOMER_INFO');
      expect(fsm.errorMessage).toContain('Invalid transition');
    });

    it('rejects transition if email is invalid', () => {
      const success = fsm.transition('DELIVERY_TIER', { ...validData, customerEmail: 'notanemail' });
      expect(success).toBe(false);
      expect(fsm.step).toBe('CUSTOMER_INFO');
    });

    it('rejects transition if shipping address is too short', () => {
      const success = fsm.transition('DELIVERY_TIER', { ...validData, shippingAddress: 'abc' });
      expect(success).toBe(false);
      expect(fsm.step).toBe('CUSTOMER_INFO');
    });
  });

  describe('DELIVERY_TIER -> PAYMENT transition', () => {
    beforeEach(() => {
      fsm.transition('DELIVERY_TIER', validData);
    });

    it('allows transition with selected delivery method', () => {
      const success = fsm.transition('PAYMENT', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('PAYMENT');
    });

    it('rejects transition if delivery method is empty', () => {
      const success = fsm.transition('PAYMENT', { ...validData, deliveryMethod: '' });
      expect(success).toBe(false);
      expect(fsm.step).toBe('DELIVERY_TIER');
    });

    it('allows going back to CUSTOMER_INFO', () => {
      const success = fsm.transition('CUSTOMER_INFO', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('CUSTOMER_INFO');
    });
  });

  describe('PAYMENT -> PROCESSING transition', () => {
    beforeEach(() => {
      fsm.transition('DELIVERY_TIER', validData);
      fsm.transition('PAYMENT', validData);
    });

    it('allows transition to PROCESSING with SIMULATED_APPROVED', () => {
      const success = fsm.transition('PROCESSING', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('PROCESSING');
    });

    it('allows transition to PROCESSING with SIMULATED_DECLINED', () => {
      const success = fsm.transition('PROCESSING', { ...validData, paymentMethod: 'SIMULATED_DECLINED' });
      expect(success).toBe(true);
      expect(fsm.step).toBe('PROCESSING');
    });

    it('rejects transition to PROCESSING with unrecognized payment method', () => {
      const success = fsm.transition('PROCESSING', { ...validData, paymentMethod: 'CRYPTO_UNKNOWN' });
      expect(success).toBe(false);
      expect(fsm.step).toBe('PAYMENT');
    });

    it('allows going back to DELIVERY_TIER', () => {
      const success = fsm.transition('DELIVERY_TIER', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('DELIVERY_TIER');
    });
  });

  describe('PROCESSING and Terminal States', () => {
    beforeEach(() => {
      fsm.transition('DELIVERY_TIER', validData);
      fsm.transition('PAYMENT', validData);
      fsm.transition('PROCESSING', validData);
    });

    it('transitions to CONFIRMED from PROCESSING', () => {
      const success = fsm.transition('CONFIRMED', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('CONFIRMED');
    });

    it('transitions to FAILED from PROCESSING', () => {
      const success = fsm.transition('FAILED', validData);
      expect(success).toBe(true);
      expect(fsm.step).toBe('FAILED');
    });

    it('does not allow arbitrary transitions directly to CONFIRMED without PROCESSING', () => {
      const freshFsm = new CheckoutStateMachine();
      expect(freshFsm.canTransitionTo('CONFIRMED', validData)).toBe(false);
    });

    it('does not allow going back to CUSTOMER_INFO while PROCESSING', () => {
      expect(fsm.canTransitionTo('CUSTOMER_INFO', validData)).toBe(false);
    });
  });

  describe('Error handling, reset and retry', () => {
    it('supports forceFail with custom error message', () => {
      fsm.forceFail('Payment gateway unreachable');
      expect(fsm.step).toBe('FAILED');
      expect(fsm.errorMessage).toBe('Payment gateway unreachable');
    });

    it('allows retry from FAILED state back to PAYMENT', () => {
      fsm.forceFail('Payment declined');
      fsm.retry();
      expect(fsm.step).toBe('PAYMENT');
      expect(fsm.errorMessage).toBeNull();
    });

    it('does nothing on retry if not in FAILED state', () => {
      fsm.retry();
      expect(fsm.step).toBe('CUSTOMER_INFO');
    });

    it('resets completely to CUSTOMER_INFO', () => {
      fsm.transition('DELIVERY_TIER', validData);
      fsm.transition('PAYMENT', validData);
      fsm.reset();
      expect(fsm.step).toBe('CUSTOMER_INFO');
      expect(fsm.errorMessage).toBeNull();
    });

    it('returns false for unknown target step', () => {
      expect(fsm.canTransitionTo('UNKNOWN_STEP' as any, validData)).toBe(false);
    });
  });
});
