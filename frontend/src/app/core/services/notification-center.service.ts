import { Injectable, computed, signal, inject } from '@angular/core';
import { ToastService } from './toast.service';
import { KeycloakService } from '../auth/keycloak.service';

export interface SystemNotification {
  id: string;
  title: string;
  message: string;
  type: 'success' | 'info' | 'warning' | 'error';
  timestamp: Date;
  read: boolean;
}

@Injectable({
  providedIn: 'root'
})
export class NotificationCenterService {
  private readonly STORAGE_KEY = 'microservices_notifications_history';
  private readonly toastService = inject(ToastService);
  private readonly keycloakService = inject(KeycloakService);

  readonly notifications = signal<SystemNotification[]>(this.loadFromStorage());

  readonly unreadCount = computed(() =>
    this.notifications().filter(n => !n.read).length
  );

  constructor() {
    // Connect to Server-Sent Events stream
    this.connectSseStream();

    // If there are no notifications, add an initial friendly welcome notification
    if (this.notifications().length === 0) {
      this.addNotification({
        title: 'Welcome to MicroStore!',
        message: 'Explore our curated hardware catalog with verified customer ratings and express delivery.',
        type: 'info'
      });
    }
  }

  private connectSseStream(): void {
    if (typeof window === 'undefined' || typeof EventSource === 'undefined') return;

    try {
      const eventSource = new EventSource('/api/notifications/stream');

      eventSource.addEventListener('ORDER_NOTIFICATION', (event: MessageEvent) => {
        try {
          // Only show order notifications if user is authenticated
          if (!this.keycloakService.isAuthenticated()) {
            return;
          }

          const data = JSON.parse(event.data);
          const isCancelled = data.orderStatus === 'CANCELLED';
          const shortOrder = data.orderNumber ? data.orderNumber.substring(0, 8).toUpperCase() : '';
          const tracking = data.trackingNumber || 'DHL Express';

          const title = isCancelled ? `Order #${shortOrder} Cancelled` : `Order #${shortOrder} Confirmed!`;
          const message = isCancelled 
            ? `Your order #${shortOrder} was cancelled and your refund has been processed.` 
            : `Your order is confirmed and being prepared for shipment via ${tracking}.`;
          const type = isCancelled ? 'warning' : 'success';

          this.addNotification({ title, message, type });
          this.toastService.show(type, title, message);
        } catch {
          // Ignore JSON parse errors
        }
      });

      eventSource.onerror = () => {
        // EventSource will automatically retry with exponential backoff
      };
    } catch {
      // Ignore initial connection failure in test environments
    }
  }

  addNotification(notification: Omit<SystemNotification, 'id' | 'timestamp' | 'read'>): void {
    const newNotif: SystemNotification = {
      ...notification,
      id: crypto.randomUUID(),
      timestamp: new Date(),
      read: false
    };

    this.notifications.update(current => {
      const updated = [newNotif, ...current].slice(0, 30); // Keep the last 30 entries
      this.saveToStorage(updated);
      return updated;
    });
  }

  markAsRead(id: string): void {
    this.notifications.update(current => {
      const updated = current.map(n => n.id === id ? { ...n, read: true } : n);
      this.saveToStorage(updated);
      return updated;
    });
  }

  markAllAsRead(): void {
    this.notifications.update(current => {
      const updated = current.map(n => ({ ...n, read: true }));
      this.saveToStorage(updated);
      return updated;
    });
  }

  clearAll(): void {
    this.notifications.set([]);
    this.saveToStorage([]);
  }

  private loadFromStorage(): SystemNotification[] {
    try {
      const data = sessionStorage.getItem(this.STORAGE_KEY);
      if (!data) return [];
      const parsed = JSON.parse(data);
      return parsed.map((item: any) => ({
        ...item,
        timestamp: new Date(item.timestamp)
      }));
    } catch {
      return [];
    }
  }

  private saveToStorage(notifications: SystemNotification[]): void {
    try {
      sessionStorage.setItem(this.STORAGE_KEY, JSON.stringify(notifications));
    } catch {
      // Ignore storage quota errors
    }
  }
}
