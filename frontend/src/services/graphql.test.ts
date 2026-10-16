import { afterEach, describe, expect, it, vi } from 'vitest';

vi.mock('./keycloak', () => ({
  getValidAccessToken: vi.fn(async (fallbackToken?: string) => fallbackToken),
}));

import { submitDeliverOrder, submitShipOrder } from './graphql';

describe('order fulfillment GraphQL mutations', () => {
  afterEach(() => vi.unstubAllGlobals());

  it.each([
    ['shipOrder', submitShipOrder, 'SHIPPED'],
    ['deliverOrder', submitDeliverOrder, 'DELIVERED'],
  ] as const)('%s sends the order ID and bearer token, then returns the persisted order', async (field, submit, status) => {
    const order = { id: '42', orderNumber: 'ORD-42', orderStatus: status, trackingNumber: 'DEMO-42', carrier: 'DHL Express' };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { [field]: order } }),
    });
    vi.stubGlobal('fetch', fetchMock);

    await expect(submit('42', 'admin-access-token')).resolves.toEqual(order);

    expect(fetchMock).toHaveBeenCalledOnce();
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('/graphql');
    expect(init.headers).toMatchObject({ Authorization: 'Bearer admin-access-token' });
    expect(JSON.parse(String(init.body))).toMatchObject({ variables: { id: '42' } });
    expect(JSON.parse(String(init.body)).query).toContain(`${field}(id: $id)`);
  });

  it('fetchProducts merges products and inventories into unified catalog', async () => {
    const { fetchProducts } = await import('./graphql');
    const mockProducts = [
      { id: '1', sku: 'LAPTOP-PRO', name: 'Laptop Pro', price: 1200 },
      { id: '2', sku: 'MOUSE-01', name: 'Mouse', price: 50 },
    ];
    const mockInventories = [
      { id: 10, sku: 'LAPTOP-PRO', quantity: 8, isInStock: true },
      { id: 11, sku: 'MOUSE-01', quantity: 0, isInStock: false },
    ];

    const fetchMock = vi.fn().mockImplementation(async (_url, init) => {
      const body = JSON.parse(String(init.body));
      if (body.query.includes('products {')) {
        return { ok: true, json: async () => ({ data: { products: mockProducts } }) };
      }
      return { ok: true, json: async () => ({ data: { inventories: mockInventories } }) };
    });
    vi.stubGlobal('fetch', fetchMock);

    const catalog = await fetchProducts();
    expect(catalog.length).toBe(2);
    expect(catalog[0]).toMatchObject({ sku: 'LAPTOP-PRO', quantity: 8, isInStock: true });
    expect(catalog[1]).toMatchObject({ sku: 'MOUSE-01', quantity: 0, isInStock: false });
  });

  it('fetchInventories returns inventory list directly', async () => {
    const { fetchInventories } = await import('./graphql');
    const mockInventories = [{ id: 1, sku: 'KEYBOARD', quantity: 15, isInStock: true }];
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { inventories: mockInventories } }),
    }));

    const result = await fetchInventories();
    expect(result).toEqual(mockInventories);
  });

  it('fetchOrders retrieves order list when user is authenticated', async () => {
    const { fetchOrders } = await import('./graphql');
    const mockOrders = [{ id: '1', orderNumber: 'ORD-1', totalAmount: 100, orderStatus: 'PLACED' }];
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { orders: mockOrders } }),
    }));

    const result = await fetchOrders('valid-token');
    expect(result).toEqual(mockOrders);
  });

  it('submitPlaceOrder executes mutation with idempotency key', async () => {
    const { submitPlaceOrder } = await import('./graphql');
    const placedOrder = { id: '99', orderNumber: 'ORD-99', totalAmount: 250, orderStatus: 'PLACED' };
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { placeOrder: placedOrder } }),
    });
    vi.stubGlobal('fetch', fetchMock);

    const result = await submitPlaceOrder(
      { customerName: 'Alex', customerEmail: 'alex@novashop.dev', items: [] } as any,
      'user-token',
      'idempotency-key-xyz'
    );
    expect(result).toEqual(placedOrder);
    expect(fetchMock).toHaveBeenCalledWith(
      '/graphql',
      expect.objectContaining({
        headers: expect.objectContaining({
          'X-Idempotency-Key': 'idempotency-key-xyz',
          Authorization: 'Bearer user-token',
        }),
      })
    );
  });

  it('submitCancelOrder executes mutation and cancels order', async () => {
    const { submitCancelOrder } = await import('./graphql');
    const cancelled = { id: '55', orderNumber: 'ORD-55', orderStatus: 'CANCELLED' };
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { cancelOrder: cancelled } }),
    }));

    const result = await submitCancelOrder('55', 'user-token');
    expect(result.orderStatus).toBe('CANCELLED');
  });

  it('throws descriptive error on GraphQL error response', async () => {
    const { fetchInventories } = await import('./graphql');
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ errors: [{ message: 'Service timeout' }] }),
    }));

    await expect(fetchInventories()).rejects.toThrow('Service timeout');
  });
});
