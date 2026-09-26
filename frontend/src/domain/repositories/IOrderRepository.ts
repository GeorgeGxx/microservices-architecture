import { Order, PlaceOrderInput } from '../../types';

export interface IOrderRepository {
  getOrders(token?: string): Promise<Order[]>;
  placeOrder(input: PlaceOrderInput, token?: string, idempotencyKey?: string): Promise<Order>;
  cancelOrder(id: string, token?: string): Promise<Order>;
}
