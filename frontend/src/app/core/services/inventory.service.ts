import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, timeout, retry } from 'rxjs';
import { environment } from '../../../environments/environment';
import { InventoryRequest, InventoryResponse } from '../models/inventory.model';

@Injectable({
  providedIn: 'root'
})
export class InventoryService {
  private readonly http = inject(HttpClient);
  private readonly apiUrl = `${environment.gatewayUrl}/api/inventory`;

  isInStock(sku: string): Observable<boolean> {
    return this.http.get<boolean>(`${this.apiUrl}/${sku}`).pipe(
      timeout(10000),
      retry({ count: 2, delay: 1000 })
    );
  }

  getAllInventory(): Observable<InventoryResponse[]> {
    return this.http.get<InventoryResponse[]>(this.apiUrl).pipe(
      timeout(10000),
      retry({ count: 2, delay: 1000 })
    );
  }

  getInventoryDetail(sku: string): Observable<InventoryResponse> {
    return this.http.get<InventoryResponse>(`${this.apiUrl}/detail/${sku}`);
  }

  saveOrUpdateStock(request: InventoryRequest): Observable<InventoryResponse> {
    return this.http.post<InventoryResponse>(this.apiUrl, request);
  }

  updateStock(sku: string, quantity: number): Observable<InventoryResponse> {
    return this.http.put<InventoryResponse>(`${this.apiUrl}/${sku}?quantity=${quantity}`, {});
  }
}
