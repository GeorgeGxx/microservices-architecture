import { describe, it, expect } from 'vitest';
import { extractApiErrorMessage } from './api';

describe('extractApiErrorMessage', () => {
  it('extracts field-level validation errors into a human-readable list', () => {
    const errorJson = JSON.stringify({
      timestamp: '2026-10-15T22:00:00Z',
      status: 400,
      error: 'Validation Failed',
      message: 'sku: sku must match ^[A-Z0-9\\-]{6,20}$',
      fields: {
        sku: 'sku must match ^[A-Z0-9\\-]{6,20}$',
        name: 'name cannot be blank'
      }
    });

    const result = extractApiErrorMessage(errorJson, 400, 'Failed to create product');
    expect(result).toBe('sku: sku must match ^[A-Z0-9\\-]{6,20}$, name: name cannot be blank');
  });

  it('falls back to detail when fields are not present', () => {
    const errorJson = JSON.stringify({
      timestamp: '2026-10-15T22:00:00Z',
      status: 400,
      detail: 'Inventory SKU not found'
    });

    const result = extractApiErrorMessage(errorJson, 400, 'Failed to update stock');
    expect(result).toBe('Inventory SKU not found');
  });

  it('falls back to message when fields and detail are absent', () => {
    const errorJson = JSON.stringify({
      timestamp: '2026-10-15T22:00:00Z',
      status: 400,
      message: 'Product SKU already exists'
    });

    const result = extractApiErrorMessage(errorJson, 400, 'Failed to create product');
    expect(result).toBe('Product SKU already exists');
  });

  it('falls back to error string if only error is present', () => {
    const errorJson = JSON.stringify({
      status: 403,
      error: 'Forbidden'
    });

    const result = extractApiErrorMessage(errorJson, 403, 'Request failed');
    expect(result).toBe('Forbidden');
  });

  it('falls back to raw text or default prefix on non-JSON payload', () => {
    const rawError = 'Internal Server Error';
    const result = extractApiErrorMessage(rawError, 500, 'Server Error');
    expect(result).toBe('Internal Server Error');

    const emptyResult = extractApiErrorMessage('', 500, 'Server Error');
    expect(emptyResult).toBe('Server Error [HTTP 500]');
  });
});

describe('fetchInventoryBySku', () => {
  it('returns parsed inventory detail when response is ok', async () => {
    const mockDetail = { id: 1, sku: 'LAPTOP-PRO-01', quantity: 15, isInStock: true };
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => ({
      ok: true,
      status: 200,
      json: async () => mockDetail,
    } as Response);

    try {
      const { fetchInventoryBySku } = await import('./api');
      const result = await fetchInventoryBySku('LAPTOP-PRO-01');
      expect(result).toEqual(mockDetail);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it('returns null on 404 status', async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = async () => ({
      ok: false,
      status: 404,
    } as Response);

    try {
      const { fetchInventoryBySku } = await import('./api');
      const result = await fetchInventoryBySku('NON-EXISTENT');
      expect(result).toBeNull();
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

