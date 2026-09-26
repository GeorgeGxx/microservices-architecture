import { IOrderRepository } from '../../domain/repositories/IOrderRepository';
import { Order, PlaceOrderInput } from '../../types';
import { fetchOrders, submitPlaceOrder, submitCancelOrder } from '../../services/graphql';

export class GraphQLOrderRepository implements IOrderRepository {
  async getOrders(token?: string): Promise<Order[]> {
    return await fetchOrders(token);
  }

  async placeOrder(
    input: PlaceOrderInput,
    token?: string,
    idempotencyKey?: string
  ): Promise<Order> {
    return await submitPlaceOrder(input, token, idempotencyKey);
  }

  async cancelOrder(id: string, token?: string): Promise<Order> {
    return await submitCancelOrder(id, token);
  }
}

export const orderRepository = new GraphQLOrderRepository();
