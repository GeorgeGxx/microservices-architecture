import { AppNotification } from '../types';

export type NotificationListener = (notification: AppNotification) => void;

export interface OrderStatusEvent {
  orderNumber: string;
  orderStatus: 'PLACED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED';
}

const ORDER_STATUSES = new Set<OrderStatusEvent['orderStatus']>(['PLACED', 'SHIPPED', 'DELIVERED', 'CANCELLED']);

export function parseOrderStatusEvent(data: string): OrderStatusEvent | null {
  try {
    const raw: unknown = JSON.parse(data);
    if (!raw || typeof raw !== 'object') return null;
    const event = raw as Record<string, unknown>;
    if (typeof event.orderNumber !== 'string' || !event.orderNumber.trim()) return null;
    if (typeof event.orderStatus !== 'string') return null;
    const orderStatus = event.orderStatus.trim().toUpperCase() as OrderStatusEvent['orderStatus'];
    return ORDER_STATUSES.has(orderStatus) ? { orderNumber: event.orderNumber, orderStatus } : null;
  } catch {
    return null;
  }
}

class SSEService {
  private eventSource: EventSource | null = null;
  private listeners: Set<NotificationListener> = new Set();
  private orderStatusListeners: Set<(event: OrderStatusEvent) => void> = new Set();
  private reconnectTimeout: NodeJS.Timeout | null = null;

  connect() {
    if (this.eventSource) return;

    try {
      this.eventSource = new EventSource('/api/notifications/stream');

      this.eventSource.onopen = () => {
        console.log('⚡ Connected to real-time SSE Notification Stream');
      };

      this.eventSource.onmessage = (event) => {
        try {
          const raw = JSON.parse(event.data);
          const notification: AppNotification = {
            id: `notif-${Date.now()}-${Math.random().toString(36).substr(2, 4)}`,
            title: raw.title || 'Order Event Update',
            message: raw.message || (raw.orderNumber ? `Order #${raw.orderNumber} status changed to ${raw.orderStatus || 'updated'}` : event.data),
            type: raw.type || 'order',
            timestamp: new Date(),
            read: false,
            orderNumber: raw.orderNumber,
          };
          this.broadcast(notification);
        } catch {
          const notification: AppNotification = {
            id: `notif-${Date.now()}`,
            title: 'System Notification',
            message: event.data,
            type: 'system',
            timestamp: new Date(),
            read: false,
          };
          this.broadcast(notification);
        }
      };

      // Spring emits order changes as a named SSE event, so onmessage does not receive them.
      this.eventSource.addEventListener('ORDER_NOTIFICATION', (event: MessageEvent<string>) => {
        const orderEvent = parseOrderStatusEvent(event.data);
        if (!orderEvent) return;
        this.orderStatusListeners.forEach((listener) => listener(orderEvent));
      });

      this.eventSource.onerror = () => {
        if (this.eventSource) {
          this.eventSource.close();
          this.eventSource = null;
        }
        // Graceful reconnect retry backoff
        if (!this.reconnectTimeout) {
          this.reconnectTimeout = setTimeout(() => {
            this.reconnectTimeout = null;
            this.connect();
          }, 5000);
        }
      };
    } catch (e) {
      console.warn('SSE subscription notice:', e);
    }
  }

  subscribe(listener: NotificationListener) {
    this.listeners.add(listener);
    if (!this.eventSource) {
      this.connect();
    }
    return () => {
      this.listeners.delete(listener);
    };
  }

  subscribeOrderStatus(listener: (event: OrderStatusEvent) => void) {
    this.orderStatusListeners.add(listener);
    if (!this.eventSource) this.connect();
    return () => this.orderStatusListeners.delete(listener);
  }

  private broadcast(notification: AppNotification) {
    this.listeners.forEach((listener) => listener(notification));
  }
}

export const sseService = new SSEService();
