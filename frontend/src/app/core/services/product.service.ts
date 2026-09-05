import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, timeout, retry, tap } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ProductRequest, ProductResponse } from '../models/product.model';
import { 
  cacheMultipleProductsInStorage, 
  cacheProductInStorage, 
  getCachedProductBySku, 
  getProductImageUrl 
} from '../utils/product-image.helper';

@Injectable({
  providedIn: 'root'
})
export class ProductService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.gatewayUrl}/api/product`;

  readonly productsMap = signal<Map<string, ProductResponse>>(new Map());

  constructor() {
    this.hydrateFromStorage();
  }

  private hydrateFromStorage(): void {
    try {
      if (typeof localStorage !== 'undefined') {
        const raw = localStorage.getItem('msa_product_cache');
        if (raw) {
          const cache = JSON.parse(raw);
          const map = new Map<string, ProductResponse>();
          for (const key of Object.keys(cache)) {
            map.set(key.toUpperCase(), cache[key]);
          }
          this.productsMap.set(map);
        }
      }
    } catch {}
  }

  getProducts(): Observable<ProductResponse[]> {
    return this.http.get<ProductResponse[]>(this.apiUrl).pipe(
      timeout(10000),
      retry({ count: 2, delay: 1000 }),
      tap(products => {
        if (Array.isArray(products)) {
          this.cacheProducts(products);
        }
      })
    );
  }

  cacheProducts(products: Array<ProductResponse | ProductRequest>): void {
    if (!Array.isArray(products)) return;
    cacheMultipleProductsInStorage(products);
    const map = new Map<string, ProductResponse>(this.productsMap());
    for (const p of products) {
      if (p?.sku) {
        map.set(p.sku.toUpperCase(), p as ProductResponse);
      }
    }
    this.productsMap.set(map);
  }

  createProduct(product: ProductRequest): Observable<void> {
    return this.http.post<void>(this.apiUrl, product).pipe(
      tap(() => {
        cacheProductInStorage(product);
        const map = new Map<string, ProductResponse>(this.productsMap());
        map.set(product.sku.toUpperCase(), product as ProductResponse);
        this.productsMap.set(map);
      })
    );
  }

  updateProduct(id: number, product: ProductRequest): Observable<void> {
    return this.http.put<void>(`${this.apiUrl}/${id}`, product).pipe(
      tap(() => {
        cacheProductInStorage(product);
        const map = new Map<string, ProductResponse>(this.productsMap());
        map.set(product.sku.toUpperCase(), product as ProductResponse);
        this.productsMap.set(map);
      })
    );
  }

  deleteProduct(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }

  getProductBySku(sku?: string): ProductResponse | undefined {
    if (!sku) return undefined;
    return this.productsMap().get(sku.toUpperCase()) || (getCachedProductBySku(sku) as ProductResponse | undefined);
  }

  getProductImage(sku?: string, fallbackName?: string): string {
    const prod = this.getProductBySku(sku);
    if (prod?.imageUrl && prod.imageUrl.trim().length > 0) {
      return prod.imageUrl.trim();
    }
    return getProductImageUrl(prod || { sku, name: fallbackName });
  }

  getProductName(sku?: string): string {
    const prod = this.getProductBySku(sku);
    return prod?.name || sku || '';
  }
}
