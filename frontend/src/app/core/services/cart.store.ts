import { Injectable, computed, inject, signal } from '@angular/core';
import { ProductResponse } from '../models/product.model';
import { CurrencyService } from './currency.service';

export interface CartItem {
  product: ProductResponse;
  quantity: number;
}

const CART_STORAGE_KEY = 'msa_cart_items';

@Injectable({
  providedIn: 'root'
})
export class CartStore {
  private readonly currencyService = inject(CurrencyService);
  private readonly itemsSignal = signal<CartItem[]>(this.loadInitialCart());

  readonly items = this.itemsSignal.asReadonly();

  readonly itemCount = computed(() =>
    this.itemsSignal().reduce((sum, item) => sum + item.quantity, 0)
  );

  readonly totalAmount = computed(() => {
    return this.itemsSignal().reduce((sum, item) => {
      const price = this.currencyService.getProductPrice(item.product);
      return sum + (price * item.quantity);
    }, 0);
  });

  readonly isCartOpen = signal<boolean>(false);

  private loadInitialCart(): CartItem[] {
    try {
      const stored = localStorage.getItem(CART_STORAGE_KEY);
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  }

  private saveCart(items: CartItem[]): void {
    try {
      localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(items));
    } catch (e) {
      console.error('Error saving cart to localStorage', e);
    }
  }

  toggleCart(open?: boolean): void {
    if (open !== undefined) {
      this.isCartOpen.set(open);
    } else {
      this.isCartOpen.update(v => !v);
    }
  }

  addToCart(product: ProductResponse, quantity: number = 1): void {
    this.itemsSignal.update(items => {
      const exists = items.some(i => i.product.sku === product.sku);
      let updated: CartItem[];
      if (exists) {
        updated = items.map(i =>
          i.product.sku === product.sku
            ? { ...i, product: { ...i.product, ...product }, quantity: i.quantity + quantity }
            : i
        );
      } else {
        updated = [...items, { product, quantity }];
      }
      this.saveCart(updated);
      return updated;
    });
    this.isCartOpen.set(true);
  }

  updateQuantity(sku: string, quantity: number): void {
    if (quantity <= 0) {
      this.removeFromCart(sku);
      return;
    }
    this.itemsSignal.update(items => {
      const updated = items.map(i =>
        i.product.sku === sku ? { ...i, quantity } : i
      );
      this.saveCart(updated);
      return updated;
    });
  }

  removeFromCart(sku: string): void {
    this.itemsSignal.update(items => {
      const updated = items.filter(i => i.product.sku !== sku);
      this.saveCart(updated);
      return updated;
    });
  }

  clearCart(): void {
    this.itemsSignal.set([]);
    this.saveCart([]);
  }
}
