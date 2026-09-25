import { Injectable, signal, computed } from '@angular/core';
import { ProductResponse } from '../models/product.model';

@Injectable({
  providedIn: 'root'
})
export class ComparisonService {
  readonly items = signal<ProductResponse[]>([]);
  readonly isDrawerOpen = signal<boolean>(false);

  readonly count = computed(() => this.items().length);
  readonly canAdd = computed(() => this.items().length < 4);

  isSelected(sku: string): boolean {
    return this.items().some(p => p.sku === sku);
  }

  toggleProduct(product: ProductResponse): void {
    if (this.isSelected(product.sku)) {
      this.items.update(list => list.filter(p => p.sku !== product.sku));
    } else {
      if (this.items().length >= 4) {
        return; // Max 4 products
      }
      this.items.update(list => [...list, product]);
    }
  }

  removeProduct(sku: string): void {
    this.items.update(list => list.filter(p => p.sku !== sku));
  }

  clear(): void {
    this.items.set([]);
    this.isDrawerOpen.set(false);
  }

  openDrawer(): void {
    if (this.items().length > 0) {
      this.isDrawerOpen.set(true);
    }
  }

  closeDrawer(): void {
    this.isDrawerOpen.set(false);
  }
}
