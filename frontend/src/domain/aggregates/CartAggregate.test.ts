import { describe, expect, it } from 'vitest';
import { CartAggregate } from './CartAggregate';
import { Product } from '../../types';

describe('CartAggregate', () => {
  const p1: Product = {
    id: '1',
    sku: 'SKU-001',
    name: 'Keyboard Pro',
    price: 40,
    quantity: 10,
  };

  const p2: Product = {
    id: '2',
    sku: 'SKU-002',
    name: 'Wireless Mouse',
    price: 30,
    quantity: 5,
  };

  it('initializes with empty items and zero amounts by default', () => {
    const cart = new CartAggregate();
    expect(cart.items).toEqual([]);
    expect(cart.itemCount).toBe(0);
    expect(cart.subtotalAmount).toBe(0);
    expect(cart.totalAmount).toBe(0);
    expect(cart.shippingAmount).toBe(0);
    expect(cart.taxAmount).toBe(0);
    expect(cart.canCheckout).toBe(false);
    expect(cart.freeShippingProgressPercent).toBe(0);
    expect(cart.remainingForFreeShipping).toBe(100);
    expect(cart.qualifiesForFreeShipping).toBe(false);
  });

  it('adds new items to cart immutably', () => {
    const cart = new CartAggregate();
    const updated = cart.addItem(p1, 2);

    expect(cart.items.length).toBe(0);
    expect(updated.items.length).toBe(1);
    expect(updated.itemCount).toBe(2);
    expect(updated.subtotalAmount).toBe(80);
    expect(updated.shippingAmount).toBe(9.99); // Subtotal < 100
    expect(updated.taxAmount).toBe(6.4); // 8% of 80
    expect(updated.totalAmount).toBe(96.39);
    expect(updated.freeShippingProgressPercent).toBe(80);
    expect(updated.remainingForFreeShipping).toBe(20);
    expect(updated.qualifiesForFreeShipping).toBe(false);
    expect(updated.canCheckout).toBe(true);
  });

  it('increments quantity when adding an existing SKU', () => {
    const cart = new CartAggregate().addItem(p1, 2);
    const updated = cart.addItem(p1, 3);

    expect(updated.itemCount).toBe(5);
    expect(updated.items[0].quantity).toBe(5);
  });

  it('clamps quantity to available stock when adding or updating', () => {
    const cart = new CartAggregate().addItem(p2, 4); // stock is 5
    const updated = cart.addItem(p2, 3); // 4 + 3 = 7, but stock is 5
    expect(updated.items[0].quantity).toBe(5);

    const updatedDirectly = cart.updateQuantity(p2.sku, 99);
    expect(updatedDirectly.items[0].quantity).toBe(5);
  });

  it('removes item if updated quantity is zero or negative', () => {
    const cart = new CartAggregate().addItem(p1, 2);
    const updatedZero = cart.updateQuantity(p1.sku, 0);
    expect(updatedZero.items.length).toBe(0);

    const updatedNegative = cart.updateQuantity(p1.sku, -1);
    expect(updatedNegative.items.length).toBe(0);
  });

  it('removes item by SKU', () => {
    const cart = new CartAggregate().addItem(p1, 1).addItem(p2, 1);
    expect(cart.items.length).toBe(2);

    const updated = cart.removeItem(p1.sku);
    expect(updated.items.length).toBe(1);
    expect(updated.items[0].product.sku).toBe(p2.sku);
  });

  it('qualifies for free shipping when subtotal reaches threshold', () => {
    const cart = new CartAggregate().addItem(p1, 3); // 3 * 40 = 120 >= 100
    expect(cart.qualifiesForFreeShipping).toBe(true);
    expect(cart.shippingAmount).toBe(0);
    expect(cart.remainingForFreeShipping).toBe(0);
    expect(cart.freeShippingProgressPercent).toBe(100);
  });

  it('clears all items cleanly', () => {
    const cart = new CartAggregate().addItem(p1, 2).addItem(p2, 1);
    const cleared = cart.clear();
    expect(cleared.items.length).toBe(0);
    expect(cleared.itemCount).toBe(0);
  });

  it('converts subtotal and total to Money value objects', () => {
    const cart = new CartAggregate().addItem(p1, 2);
    const subtotalMoney = cart.getMoneySubtotal('USD');
    const totalMoney = cart.getMoneyTotal('USD');
    expect(subtotalMoney.amount).toBe(80);
    expect(totalMoney.amount).toBe(96.39);
  });

  it('ignores updateQuantity for SKUs not present in the cart', () => {
    const cart = new CartAggregate().addItem(p1, 1);
    const unchanged = cart.updateQuantity('NON-EXISTENT-SKU', 5);
    expect(unchanged.items.length).toBe(1);
    expect(unchanged.items[0].product.sku).toBe(p1.sku);
  });
});

