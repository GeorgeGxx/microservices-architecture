import { Injectable, signal, computed } from '@angular/core';
import { ProductResponse } from '../models/product.model';

const WISHLIST_KEY = 'msa_wishlist_skus';

@Injectable({
  providedIn: 'root'
})
export class WishlistService {
  private readonly wishlistSkusSignal = signal<string[]>(this.loadInitial());

  readonly wishlistSkus = this.wishlistSkusSignal.asReadonly();
  readonly count = computed(() => this.wishlistSkusSignal().length);

  private loadInitial(): string[] {
    try {
      if (typeof localStorage !== 'undefined') {
        const stored = localStorage.getItem(WISHLIST_KEY);
        return stored ? JSON.parse(stored) : [];
      }
    } catch {}
    return [];
  }

  isFavorite(sku: string): boolean {
    return this.wishlistSkusSignal().includes(sku);
  }

  toggleFavorite(product: ProductResponse): boolean {
    const sku = product.sku;
    let isAdded = false;
    this.wishlistSkusSignal.update(skus => {
      if (skus.includes(sku)) {
        const next = skus.filter(s => s !== sku);
        this.save(next);
        return next;
      } else {
        const next = [...skus, sku];
        this.save(next);
        isAdded = true;
        return next;
      }
    });
    return isAdded;
  }

  private save(skus: string[]): void {
    try {
      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(WISHLIST_KEY, JSON.stringify(skus));
      }
    } catch {}
  }
}
