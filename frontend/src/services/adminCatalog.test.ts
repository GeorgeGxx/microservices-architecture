import { afterEach, describe, expect, it, vi } from 'vitest';

const apiMocks = vi.hoisted(() => ({
  createProduct: vi.fn(),
  saveOrUpdateStock: vi.fn(),
}));

vi.mock('./api', () => apiMocks);

import { createProductWithInitialStock } from './adminCatalog';

const payload = { sku: 'SKU-TEST-1', name: 'Test product', price: 12, status: true };

describe('admin product and inventory setup', () => {
  afterEach(() => vi.clearAllMocks());

  it('does not call inventory when products-service rejects product creation', async () => {
    apiMocks.createProduct.mockRejectedValueOnce(new Error('catalog unavailable'));

    await expect(createProductWithInitialStock(payload, 8, 'admin-token')).rejects.toThrow('catalog unavailable');
    expect(apiMocks.saveOrUpdateStock).not.toHaveBeenCalled();
  });

  it('reports inventory failure as a recoverable partial result after product creation', async () => {
    apiMocks.createProduct.mockResolvedValueOnce(undefined);
    apiMocks.saveOrUpdateStock.mockRejectedValueOnce(new Error('inventory unavailable'));

    await expect(createProductWithInitialStock(payload, 8, 'admin-token')).resolves.toMatchObject({
      inventoryInitialized: false,
      inventoryError: expect.objectContaining({ message: 'inventory unavailable' }),
    });
    expect(apiMocks.createProduct).toHaveBeenCalledOnce();
    expect(apiMocks.saveOrUpdateStock).toHaveBeenCalledWith({ sku: payload.sku, quantity: 8 }, 'admin-token');
  });

  it('reports full success only after both services succeed', async () => {
    apiMocks.createProduct.mockResolvedValueOnce(undefined);
    apiMocks.saveOrUpdateStock.mockResolvedValueOnce(undefined);

    await expect(createProductWithInitialStock(payload, 0, 'admin-token')).resolves.toEqual({ inventoryInitialized: true });
    expect(apiMocks.saveOrUpdateStock).toHaveBeenCalledWith({ sku: payload.sku, quantity: 0 }, 'admin-token');
  });
});
