import { describe, expect, it, vi, afterEach } from 'vitest';
import { checkStorefrontApiHealth } from './storefrontHealth';

describe('checkStorefrontApiHealth', () => {
  const originalFetch = globalThis.fetch;

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it('returns healthy when Apollo Federation returns products without errors', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: {
          products: [{ sku: 'LAPTOP-PRO' }],
        },
      }),
    } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('healthy');
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/graphql',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      })
    );
  });

  it('returns throttled when response status is 429', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 429,
    } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('throttled');
  });

  it('returns throttled when /graphql fails but /router-health succeeds', async () => {
    globalThis.fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: false,
        status: 503,
      } as Response)
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
      } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('throttled');
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/router-health',
      expect.anything()
    );
  });

  it('returns unavailable when /graphql fails and /router-health also fails', async () => {
    globalThis.fetch = vi.fn()
      .mockResolvedValueOnce({
        ok: false,
        status: 503,
      } as Response)
      .mockResolvedValueOnce({
        ok: false,
        status: 503,
      } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('unavailable');
  });

  it('returns unavailable when GraphQL errors are returned in payload', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        errors: [{ message: 'Subgraph unreachable' }],
      }),
    } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('unavailable');
  });

  it('returns unavailable when data.products is not an array', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: { products: null },
      }),
    } as Response);

    const result = await checkStorefrontApiHealth();
    expect(result).toBe('unavailable');
  });
});
