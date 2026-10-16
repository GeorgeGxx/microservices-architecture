import { describe, expect, it, vi, afterEach } from 'vitest';
import { checkStorefrontApiHealth } from './storefrontHealth';

describe('checkStorefrontApiHealth', () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it('returns true when Apollo Federation returns products without errors', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: {
          products: [{ sku: 'LAPTOP-PRO' }],
        },
      }),
    } as Response);

    const isHealthy = await checkStorefrontApiHealth();
    expect(isHealthy).toBe(true);
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/graphql',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      })
    );
  });

  it('returns false when response is not ok', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 503,
    } as Response);

    const isHealthy = await checkStorefrontApiHealth();
    expect(isHealthy).toBe(false);
  });

  it('returns false when GraphQL errors are returned in payload', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        errors: [{ message: 'Subgraph unreachable' }],
      }),
    } as Response);

    const isHealthy = await checkStorefrontApiHealth();
    expect(isHealthy).toBe(false);
  });

  it('returns false when data.products is not an array', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: { products: null },
      }),
    } as Response);

    const isHealthy = await checkStorefrontApiHealth();
    expect(isHealthy).toBe(false);
  });
});
