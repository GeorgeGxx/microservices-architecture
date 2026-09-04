import { Injectable, signal } from '@angular/core';
import { ProductResponse } from '../models/product.model';

export type CurrencyCode = 'USD';

export interface CurrencyConfig {
  code: CurrencyCode;
  symbol: string;
  label: string;
  flag: string;
}

@Injectable({
  providedIn: 'root'
})
export class CurrencyService {
  readonly currentCurrency = signal<CurrencyCode>('USD');

  readonly currencies: Record<CurrencyCode, CurrencyConfig> = {
    USD: { code: 'USD', symbol: '$', label: 'USD ($)', flag: '🇺🇸' }
  };

  setCurrency(curr: CurrencyCode): void {
    this.currentCurrency.set('USD');
  }

  toggleCurrency(): void {
    this.setCurrency('USD');
  }

  /**
   * Returns price in USD.
   */
  getProductPrice(product: ProductResponse): number {
    if (product.prices && product.prices['USD'] !== undefined) {
      return product.prices['USD'];
    }
    return product.price || 0;
  }
}
