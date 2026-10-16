import { describe, expect, it } from 'vitest';
import { createOrderNotification, parseOrderStatusEvent } from './sse';

describe('order status SSE contract', () => {
  it.each(['PLACED', 'SHIPPED', 'DELIVERED', 'CANCELLED'] as const)(
    'accepts persisted status %s from Orders Service',
    (orderStatus) => {
      expect(parseOrderStatusEvent(JSON.stringify({ orderNumber: 'ORD-42', orderStatus }))).toEqual({
        orderNumber: 'ORD-42',
        orderStatus,
      });
    }
  );

  it('normalizes status casing and ignores malformed or unsupported events', () => {
    expect(parseOrderStatusEvent('{"orderNumber":"ORD-42","orderStatus":"shipped"}')?.orderStatus).toBe('SHIPPED');
    expect(parseOrderStatusEvent('{broken')).toBeNull();
    expect(parseOrderStatusEvent('{"orderNumber":"ORD-42","orderStatus":"PREPARING"}')).toBeNull();
    expect(parseOrderStatusEvent('{"orderStatus":"DELIVERED"}')).toBeNull();
  });

  it('turns the persisted status into a concise, stable live notification', () => {
    const event = { orderNumber: 'ORD-42', orderStatus: 'SHIPPED' as const, userId: 'customer-1' };
    const notification = createOrderNotification(event);
    expect(notification).toMatchObject({
      id: 'order-ORD-42-SHIPPED',
      title: 'Order in transit',
      message: 'Order #ORD-42 is now in transit.',
      type: 'order',
      userId: 'customer-1',
    });
  });
});

describe('SSEService live connection management', () => {
  it('connects and receives general and order notifications', async () => {
    class MockEventSource {
      listeners: Record<string, ((event: any) => void)[]> = {};
      onopen: (() => void) | null = null;
      onmessage: ((event: any) => void) | null = null;
      onerror: (() => void) | null = null;
      closed = false;

      constructor(public url: string) {}

      addEventListener(type: string, cb: (event: any) => void) {
        this.listeners[type] = this.listeners[type] || [];
        this.listeners[type].push(cb);
      }

      close() {
        this.closed = true;
      }
    }

    (globalThis as any).EventSource = MockEventSource;

    const { sseService } = await import('./sse');
    const received: any[] = [];
    const unsubscribe = sseService.subscribe((n) => received.push(n));

    const activeInstance = (sseService as any).eventSource as MockEventSource;
    expect(activeInstance).toBeTruthy();

    // Trigger onopen
    activeInstance.onopen?.();

    // Trigger JSON message
    activeInstance.onmessage?.({
      data: JSON.stringify({ title: 'Welcome', message: 'Hello user', orderNumber: 'ORD-123' }),
    });
    expect(received).toHaveLength(1);
    expect(received[0].title).toBe('Welcome');

    // Trigger raw text message fallback
    activeInstance.onmessage?.({ data: 'Plain text alert' });
    expect(received).toHaveLength(2);
    expect(received[1].title).toBe('System Notification');

    // Trigger ORDER_NOTIFICATION
    const orderReceived: any[] = [];
    const unsubOrder = sseService.subscribeOrderStatus((ev) => orderReceived.push(ev));
    const orderListener = activeInstance.listeners['ORDER_NOTIFICATION']?.[0];
    orderListener?.({
      data: JSON.stringify({ orderNumber: 'ORD-999', orderStatus: 'DELIVERED' }),
    });
    expect(orderReceived).toHaveLength(1);
    expect(orderReceived[0].orderNumber).toBe('ORD-999');

    // Test error handler and reconnect
    activeInstance.onerror?.();
    expect(activeInstance.closed).toBe(true);

    // Unsubscribe all
    unsubscribe();
    unsubOrder();
  });
});

