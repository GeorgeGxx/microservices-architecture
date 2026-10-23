import { AppNotification } from '../types';
import { getOrderStatusNotificationCopy } from '../utils/orderNotificationCopy';
import { getValidAccessToken } from './keycloak';

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
  private abortController: AbortController | null = null;
  private connecting = false;
  private readonly listeners = new Map<NotificationListener, string | undefined>();
  private readonly orderStatusListeners = new Map<(event: OrderStatusEvent) => void, string | undefined>();
  private reconnectTimeout: NodeJS.Timeout | null = null;

  private async connect() {
    if (this.abortController || this.connecting || !this.hasSubscribers()) return;
    this.connecting = true;
    try {
      const fallbackToken = this.getSubscriberToken();
      const accessToken = await getValidAccessToken(fallbackToken);
      if (!accessToken || !this.hasSubscribers()) return;

      const controller = new AbortController();
      this.abortController = controller;
      const response = await fetch('/api/notifications/stream', {
        headers: { Authorization: `Bearer ${accessToken}`, Accept: 'text/event-stream' },
        signal: controller.signal,
      });
      if (!response.ok || !response.body) {
        throw new Error(`Notification stream returned HTTP ${response.status}`);
      }

      console.log('⚡ Connected to authenticated real-time SSE Notification Stream');
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      while (!controller.signal.aborted) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        const frames = buffer.split(/\r?\n\r?\n/);
        buffer = frames.pop() ?? '';
        frames.forEach((frame) => this.handleFrame(frame));
      }
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'AbortError')) {
        console.warn('SSE subscription interrupted:', error);
      }
    } finally {
      this.abortController = null;
      this.connecting = false;
      if (this.hasSubscribers()) this.scheduleReconnect();
    }
  }

  subscribe(listener: NotificationListener, token?: string) {
    this.listeners.set(listener, token);
    void this.connect();
    return () => {
      this.listeners.delete(listener);
      this.disconnectWhenIdle();
    };
  }

  subscribeOrderStatus(listener: (event: OrderStatusEvent) => void, token?: string) {
    this.orderStatusListeners.set(listener, token);
    void this.connect();
    return () => {
      this.orderStatusListeners.delete(listener);
      this.disconnectWhenIdle();
    };
  }

  private hasSubscribers() {
    return this.listeners.size > 0 || this.orderStatusListeners.size > 0;
  }

  private getSubscriberToken() {
    return [...this.listeners.values(), ...this.orderStatusListeners.values()]
      .find((token): token is string => Boolean(token));
  }

  private handleFrame(frame: string) {
    let eventName = 'message';
    const data: string[] = [];
    frame.split(/\r?\n/).forEach((line) => {
      if (line.startsWith('event:')) eventName = line.slice(6).trim();
      if (line.startsWith('data:')) data.push(line.slice(5).trimStart());
    });
    if (eventName !== 'ORDER_NOTIFICATION' || data.length === 0) return;
    const orderEvent = parseOrderStatusEvent(data.join('\n'));
    if (!orderEvent) return;
    this.broadcast(createOrderNotification(orderEvent));
    this.orderStatusListeners.forEach((_, listener) => listener(orderEvent));
  }

  private scheduleReconnect() {
    if (this.reconnectTimeout || !this.hasSubscribers()) return;
    this.reconnectTimeout = setTimeout(() => {
      this.reconnectTimeout = null;
      void this.connect();
    }, 5000);
  }

  private disconnectWhenIdle() {
    if (this.hasSubscribers()) return;
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.abortController?.abort();
    this.abortController = null;
  }

  private broadcast(notification: AppNotification) {
    this.listeners.forEach((_, listener) => listener(notification));
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
