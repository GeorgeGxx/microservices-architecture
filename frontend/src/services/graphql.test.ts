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
});
