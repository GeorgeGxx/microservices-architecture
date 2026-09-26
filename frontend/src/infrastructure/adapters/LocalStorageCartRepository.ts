import { CartItem } from '../../types';

const CART_STORAGE_KEY = 'novashop_cart_v2';

export class LocalStorageCartRepository {
  load(): CartItem[] {
    try {
      const data = localStorage.getItem(CART_STORAGE_KEY);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  save(items: ReadonlyArray<CartItem>): void {
    try {
      localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(items));
    } catch {
      // Storage unavailable / quota exceeded handled safely
    }
  }

  clear(): void {
    try {
      localStorage.removeItem(CART_STORAGE_KEY);
    } catch {
      // Handled safely
    }
  }
}

export const cartStorage = new LocalStorageCartRepository();
