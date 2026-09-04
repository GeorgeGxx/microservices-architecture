import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, timeout, retry } from 'rxjs';
import { environment } from '../../../environments/environment';
import { ProductRequest, ProductResponse } from '../models/product.model';

@Injectable({
  providedIn: 'root'
})
export class ProductService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.gatewayUrl}/api/product`;

  getProducts(): Observable<ProductResponse[]> {
    return this.http.get<ProductResponse[]>(this.apiUrl).pipe(
      timeout(10000),
      retry({ count: 2, delay: 1000 })
    );
  }

  createProduct(product: ProductRequest): Observable<void> {
    return this.http.post<void>(this.apiUrl, product);
  }

  updateProduct(id: number, product: ProductRequest): Observable<void> {
    return this.http.put<void>(`${this.apiUrl}/${id}`, product);
  }

  deleteProduct(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/${id}`);
  }
}
