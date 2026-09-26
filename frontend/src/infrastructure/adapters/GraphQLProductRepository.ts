import { IProductRepository } from '../../domain/repositories/IProductRepository';
import { Product, InventoryItem } from '../../types';
import { fetchProducts, fetchInventories } from '../../services/graphql';

export class GraphQLProductRepository implements IProductRepository {
  async getProducts(token?: string): Promise<Product[]> {
    return await fetchProducts(token);
  }

  async getInventories(token?: string): Promise<InventoryItem[]> {
    return await fetchInventories(token);
  }
}

export const productRepository = new GraphQLProductRepository();
