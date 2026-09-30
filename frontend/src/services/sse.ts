import { AppNotification } from '../types';
import { getOrderStatusNotificationCopy } from '../utils/orderNotificationCopy';

export type NotificationListener = (notification: AppNotification) => void;

export interface OrderStatusEvent {
  orderNumber: string;
  orderStatus: 'PLACED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED';
  userId?: string;
  username?: string;
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
    if (!ORDER_STATUSES.has(orderStatus)) return null;
    const userId = typeof event.userId === 'string' ? event.userId : undefined;
    const username = typeof event.username === 'string' ? event.username : undefined;
    return {
      orderNumber: event.orderNumber,
      orderStatus,
      ...(userId ? { userId } : {}),
      ...(username ? { username } : {}),
    };
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
        this.broadcast(createOrderNotification(orderEvent));
        this.orderStatusListeners.forEach((listener) => listener(orderEvent));
      });

      this.eventSource.onerror = () => {
        if (this.eventSource) {
          this.eventSource.close();
          this.eventSource = null;
        }
        if (!this.hasSubscribers()) return;
        // Graceful reconnect retry backoff
        if (!this.reconnectTimeout) {
          this.reconnectTimeout = setTimeout(() => {
            this.reconnectTimeout = null;
            if (this.hasSubscribers()) this.connect();
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
      this.disconnectWhenIdle();
    };
  }

  subscribeOrderStatus(listener: (event: OrderStatusEvent) => void) {
    this.orderStatusListeners.add(listener);
    if (!this.eventSource) this.connect();
    return () => {
      this.orderStatusListeners.delete(listener);
      this.disconnectWhenIdle();
    };
  }

  private hasSubscribers() {
    return this.listeners.size > 0 || this.orderStatusListeners.size > 0;
  }

  private disconnectWhenIdle() {
    if (this.hasSubscribers()) return;
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.eventSource?.close();
    this.eventSource = null;
  }

  private broadcast(notification: AppNotification) {
    this.listeners.forEach((listener) => listener(notification));
  }
}

export function createOrderNotification(event: OrderStatusEvent): AppNotification {
  const { title, message } = getOrderStatusNotificationCopy(event.orderStatus, event.orderNumber);

  return {
    id: `order-${event.orderNumber}-${event.orderStatus}`,
    title,
    message,
    type: 'order',
    timestamp: new Date(),
    read: false,
    orderNumber: event.orderNumber,
    userId: event.userId,
    username: event.username,
  };
}

export const sseService = new SSEService();
