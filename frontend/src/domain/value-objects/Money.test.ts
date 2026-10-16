import { describe, expect, it } from 'vitest';
import { Money } from './Money';

describe('Money Value Object', () => {
  it('creates money rounded to 2 decimal places', () => {
    const m = new Money(19.994);
    expect(m.amount).toBe(19.99);
    expect(m.currency).toBe('USD');
  });

  it('handles negative or NaN amounts safely as zero', () => {
    expect(new Money(-10).amount).toBe(0);
    expect(new Money(NaN).amount).toBe(0);
  });

  it('adds money amounts', () => {
    const m1 = new Money(10.50);
    const m2 = new Money(5.25);
    const sum = m1.add(m2);
    expect(sum.amount).toBe(15.75);
  });

  it('subtracts money amounts without going negative', () => {
    const m1 = new Money(10);
    const m2 = new Money(4);
    expect(m1.subtract(m2).amount).toBe(6);

    const m3 = new Money(20);
    expect(m1.subtract(m3).amount).toBe(0);
  });

  it('multiplies money by a factor', () => {
    const m = new Money(15.50);
    const multiplied = m.multiply(3);
    expect(multiplied.amount).toBe(46.50);
  });

  it('formats money as standard USD currency string', () => {
    const m = new Money(1234.56);
    expect(m.format()).toBe('$1,234.56');
  });

  it('checks equality between money objects', () => {
    const m1 = new Money(50.00);
    const m2 = new Money(50.00);
    const m3 = new Money(49.99);
    expect(m1.equals(m2)).toBe(true);
    expect(m1.equals(m3)).toBe(false);
  });

  it('creates zero money instance', () => {
    const zero = Money.zero();
    expect(zero.amount).toBe(0);
  });

  it('supports convertTo no-op for same currency', () => {
    const m = new Money(25);
    expect(m.convertTo('USD').amount).toBe(25);
  });
});
