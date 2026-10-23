import { describe, expect, it, vi } from 'vitest';

vi.mock('./keycloak', () => ({
  getValidAccessToken: vi.fn(async (token?: string) => token),
}));

import { createOrderNotification, parseOrderStatusEvent, sseService } from './sse';

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
  it('connects with a bearer token and receives only the minimized order status event', async () => {
    const encoder = new TextEncoder();
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(encoder.encode(
          'event: ORDER_NOTIFICATION\ndata: {"orderNumber":"ORD-999","orderStatus":"DELIVERED","userId":"customer-1"}\n\n'
        ));
        controller.close();
      },
    });
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 200, body });
    vi.stubGlobal('fetch', fetchMock);

    const received: any[] = [];
    const orderReceived: any[] = [];
    const unsubscribe = sseService.subscribe((notification) => received.push(notification), 'test-token');
    const unsubOrder = sseService.subscribeOrderStatus((ev) => orderReceived.push(ev));

    await vi.waitFor(() => expect(received).toHaveLength(1));
    expect(orderReceived).toHaveLength(1);
    expect(orderReceived[0].orderNumber).toBe('ORD-999');
    expect(received[0].orderNumber).toBe('ORD-999');
    expect(fetchMock).toHaveBeenCalledWith('/api/notifications/stream', expect.objectContaining({
      headers: expect.objectContaining({ Authorization: 'Bearer test-token' }),
    }));

    unsubscribe();
    unsubOrder();
    vi.unstubAllGlobals();
  });
});

