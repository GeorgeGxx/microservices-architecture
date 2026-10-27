export class PackageItem {
  constructor(
    public readonly sku: string,
    public readonly quantity: number,
  ) {
    if (!sku || sku.trim().length === 0) {
      throw new Error('Item SKU is required');
    }
    if (quantity === undefined || quantity === null || quantity <= 0) {
      throw new Error('Quantity must be greater than zero');
    }
  }
}
