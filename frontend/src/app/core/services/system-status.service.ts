import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { timeout, retry } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface ServiceHealth {
  id: string;
  name: string;
  category: 'gateway' | 'service' | 'auth' | 'security' | 'infrastructure';
  endpoint: string;
  status: 'UP' | 'DOWN' | 'CHECKING';
  latencyMs?: number;
  details?: string;
  lastChecked?: Date;
}

@Injectable({
  providedIn: 'root'
})
export class SystemStatusService {
  private readonly http = inject(HttpClient);

  readonly services = signal<ServiceHealth[]>([
    {
      id: 'api-gateway',
      name: 'Cloud Gateway & Edge Routing',
      category: 'gateway',
      endpoint: `${environment.gatewayUrl}/actuator/health`,
      status: 'CHECKING',
      details: 'Traffic routing, rate limiting and secure proxy'
    },
    {
      id: 'products-service',
      name: 'Product Catalog & Pricing',
      category: 'service',
      endpoint: `${environment.gatewayUrl}/actuator/products/health`,
      status: 'CHECKING',
      details: 'Product catalog, search engine and currency pricing'
    },
    {
      id: 'inventory-service',
      name: 'Real-Time Inventory Engine',
      category: 'service',
      endpoint: `${environment.gatewayUrl}/actuator/inventory/health`,
      status: 'CHECKING',
      details: 'Live stock allocations and stock validation'
    },
    {
      id: 'orders-service',
      name: 'Order Processing & Checkout',
      category: 'service',
      endpoint: `${environment.gatewayUrl}/actuator/orders/health`,
      status: 'CHECKING',
      details: 'Cart checkout and distributed transaction flow'
    },
    {
      id: 'notification-service',
      name: 'Instant Notifications & Alerts',
      category: 'service',
      endpoint: `${environment.gatewayUrl}/actuator/notification/health`,
      status: 'CHECKING',
      details: 'Real-time customer event streaming and notifications'
    },
    {
      id: 'keycloak',
      name: 'Authentication & Security (IAM)',
      category: 'auth',
      endpoint: `${environment.keycloak.url}/realms/${environment.keycloak.realm}/.well-known/openid-configuration`,
      status: 'CHECKING',
      details: 'Single sign-on, session safety and token validation'
    },
    {
      id: 'vault',
      name: 'Data Protection & Secret Vault',
      category: 'security',
      endpoint: `${environment.gatewayUrl}/actuator/vault/health`,
      status: 'CHECKING',
      details: 'Enterprise encryption and platform data protection'
    }
  ]);

  readonly isCheckingAll = signal<boolean>(false);

  checkAllServices(): void {
    this.isCheckingAll.set(true);
    const currentList = this.services();

    currentList.forEach((service, index) => {
      setTimeout(() => {
        this.checkServiceHealth(service.id);
      }, index * 120);
    });

    setTimeout(() => {
      this.isCheckingAll.set(false);
    }, currentList.length * 120 + 1000);
  }

  checkServiceHealth(serviceId: string): void {
    const service = this.services().find(s => s.id === serviceId);
    if (!service) return;

    this.updateServiceStatus(serviceId, { status: 'CHECKING' });
    const startTime = performance.now();

    this.http.get(service.endpoint, { observe: 'response', responseType: 'text' }).pipe(
      timeout(10000),
      retry({ count: 1, delay: 1000 })
    ).subscribe({
      next: () => {
        const latencyMs = Math.round(performance.now() - startTime);
        this.updateServiceStatus(serviceId, {
          status: 'UP',
          latencyMs,
          lastChecked: new Date()
        });
      },
      error: (err) => {
        // In Actuator or Keycloak, a 200, 302, 401, or 403 status code indicates the microservice is reachable and responding
        if (err.status >= 200 && err.status < 500) {
          const latencyMs = Math.round(performance.now() - startTime);
          this.updateServiceStatus(serviceId, {
            status: 'UP',
            latencyMs,
            lastChecked: new Date()
          });
        } else {
          this.updateServiceStatus(serviceId, {
            status: 'DOWN',
            latencyMs: undefined,
            lastChecked: new Date()
          });
        }
      }
    });
  }

  private updateServiceStatus(serviceId: string, updates: Partial<ServiceHealth>): void {
    this.services.update(list =>
      list.map(s => s.id === serviceId ? { ...s, ...updates } : s)
    );
  }
}
