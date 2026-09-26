import { CartItem, Product } from '../../types';
import { Money, CurrencyCode } from '../value-objects/Money';

export class CartAggregate {
  private readonly _items: CartItem[];
  public readonly freeShippingThreshold: number = 100;
  public readonly defaultShippingRate: number = 9.99;
  public readonly taxRate: number = 0.08;

  constructor(items: CartItem[] = []) {
    this._items = [...items];
  }

  public get items(): ReadonlyArray<CartItem> {
    return this._items;
  }

  public get itemCount(): number {
    return this._items.reduce((sum, item) => sum + item.quantity, 0);
  }

  public get subtotalAmount(): number {
    return this._items.reduce((sum, item) => sum + item.product.price * item.quantity, 0);
  }

  public get qualifiesForFreeShipping(): boolean {
    return this.subtotalAmount >= this.freeShippingThreshold;
  }

  public get freeShippingProgressPercent(): number {
    if (this.subtotalAmount === 0) return 0;
    return Math.min(100, Math.round((this.subtotalAmount / this.freeShippingThreshold) * 100));
  }

  public get remainingForFreeShipping(): number {
    return Math.max(0, this.freeShippingThreshold - this.subtotalAmount);
  }

  public get shippingAmount(): number {
    if (this._items.length === 0 || this.qualifiesForFreeShipping) return 0;
    return this.defaultShippingRate;
  }

  public get taxAmount(): number {
    return Math.round(this.subtotalAmount * this.taxRate * 100) / 100;
  }

  public get totalAmount(): number {
    if (this._items.length === 0) return 0;
    return Math.round((this.subtotalAmount + this.shippingAmount + this.taxAmount) * 100) / 100;
  }

  public get canCheckout(): boolean {
    return this._items.length > 0;
  }

  public addItem(product: Product, quantity = 1): CartAggregate {
    const existingIndex = this._items.findIndex((item) => item.product.sku === product.sku);
    const availableStock = product.quantity !== undefined ? product.quantity : 999;

    let updated: CartItem[];

    if (existingIndex > -1) {
      const currentQty = this._items[existingIndex].quantity;
      const targetQty = Math.min(availableStock, currentQty + quantity);
      updated = this._items.map((item, idx) =>
        idx === existingIndex ? { ...item, quantity: targetQty } : item
      );
    } else {
      const initialQty = Math.min(availableStock, Math.max(1, quantity));
      updated = [...this._items, { product, quantity: initialQty }];
    }

    return new CartAggregate(updated);
  }

  public updateQuantity(sku: string, quantity: number): CartAggregate {
    if (quantity <= 0) {
      return this.removeItem(sku);
    }

    const updated = this._items.map((item) => {
      if (item.product.sku === sku) {
        const availableStock = item.product.quantity !== undefined ? item.product.quantity : 999;
        return { ...item, quantity: Math.min(availableStock, quantity) };
      }
      return item;
    });

    return new CartAggregate(updated);
  }

  public removeItem(sku: string): CartAggregate {
    const updated = this._items.filter((item) => item.product.sku !== sku);
    return new CartAggregate(updated);
  }

  public clear(): CartAggregate {
    return new CartAggregate([]);
  }

  public getMoneySubtotal(currency: CurrencyCode): Money {
    return new Money(this.subtotalAmount, 'USD').convertTo(currency);
  }

  public getMoneyTotal(currency: CurrencyCode): Money {
    return new Money(this.totalAmount, 'USD').convertTo(currency);
  }
}
