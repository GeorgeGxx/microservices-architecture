import { CreateProductPayload, createProduct, saveOrUpdateStock } from './api';

export type ProductInventorySetupResult =
  | { inventoryInitialized: true }
  | { inventoryInitialized: false; inventoryError: unknown };

/** Creates the catalog record first, then reports inventory failure as a recoverable partial result. */
export async function createProductWithInitialStock(
  payload: CreateProductPayload,
  quantity: number,
  token?: string
): Promise<ProductInventorySetupResult> {
  await createProduct(payload, token);

  try {
    await saveOrUpdateStock({ sku: payload.sku, quantity }, token);
    return { inventoryInitialized: true };
  } catch (inventoryError: unknown) {
    return { inventoryInitialized: false, inventoryError };
  }
}
