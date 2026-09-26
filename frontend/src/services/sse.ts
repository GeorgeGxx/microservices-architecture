import { AppNotification } from '../types';

export type NotificationListener = (notification: AppNotification) => void;

class SSEService {
  private eventSource: EventSource | null = null;
  private listeners: Set<NotificationListener> = new Set();
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
            message: raw.message || raw.orderNumber ? `Order #${raw.orderNumber} status changed to ${raw.orderStatus || 'CONFIRMED'}` : event.data,
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

  private broadcast(notification: AppNotification) {
    this.listeners.forEach((listener) => listener(notification));
  }
}

export const sseService = new SSEService();
