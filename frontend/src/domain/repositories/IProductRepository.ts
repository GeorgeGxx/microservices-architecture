import { Product, InventoryItem } from '../../types';

export interface IProductRepository {
  getProducts(token?: string): Promise<Product[]>;
  getInventories(token?: string): Promise<InventoryItem[]>;
}
