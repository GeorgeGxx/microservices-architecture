import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, timeout, retry } from 'rxjs';
import { environment } from '../../../environments/environment';
import { OrderRequest, OrderResponse } from '../models/order.model';

@Injectable({
  providedIn: 'root'
})
export class OrderService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.gatewayUrl}/api/order`;

  getOrders(): Observable<OrderResponse[]> {
    return this.http.get<OrderResponse[]>(this.apiUrl).pipe(
      timeout(10000),
      retry({ count: 2, delay: 1000 })
    );
  }

  placeOrder(orderRequest: OrderRequest, idempotencyKey?: string): Observable<OrderResponse> {
    const key = idempotencyKey || (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : undefined);
    const headers: Record<string, string> = {};
    if (key) {
      headers['X-Idempotency-Key'] = key;
    }
    return this.http.post<OrderResponse>(this.apiUrl, orderRequest, { headers });
  }

  cancelOrder(id: number): Observable<OrderResponse> {
    return this.http.put<OrderResponse>(`${this.apiUrl}/${id}/cancel`, {});
  }

  shipOrder(id: number): Observable<OrderResponse> {
    return this.http.put<OrderResponse>(`${this.apiUrl}/${id}/ship`, {});
  }

  deliverOrder(id: number): Observable<OrderResponse> {
    return this.http.put<OrderResponse>(`${this.apiUrl}/${id}/deliver`, {});
  }
}
