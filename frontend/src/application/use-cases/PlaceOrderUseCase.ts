import { Order, PlaceOrderInput, CartItem } from '../../types';
import { IOrderRepository } from '../../domain/repositories/IOrderRepository';
import { orderRepository } from '../../infrastructure/adapters/GraphQLOrderRepository';

export interface PlaceOrderRequest {
  items: ReadonlyArray<CartItem>;
  customerName: string;
  customerEmail: string;
  shippingAddress: string;
  city: string;
  postalCode: string;
  phone: string;
  deliveryMethod: string;
  paymentMethod: string;
}

export class PlaceOrderUseCase {
  constructor(private readonly orderRepo: IOrderRepository = orderRepository) {}

  async execute(request: PlaceOrderRequest, token?: string): Promise<Order> {
    if (request.items.length === 0) {
      throw new Error('Cart cannot be empty to place an order.');
    }

    if (!request.customerEmail || !request.customerEmail.includes('@')) {
      throw new Error('Please provide a valid email address.');
    }

    if (!request.shippingAddress || request.shippingAddress.trim().length < 5) {
      throw new Error('Shipping address is required and must include street details.');
    }

    // Generate cryptographic UUIDv4 for Idempotency
    const idempotencyKey =
      typeof crypto !== 'undefined' && crypto.randomUUID
        ? crypto.randomUUID()
        : `idemp-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;

    const orderInput: PlaceOrderInput = {
      customerName: request.customerName,
      customerEmail: request.customerEmail,
      shippingAddress: request.shippingAddress,
      city: request.city,
      postalCode: request.postalCode,
      phone: request.phone,
      deliveryMethod: request.deliveryMethod,
      paymentMethod: request.paymentMethod,
      orderItems: request.items.map((item) => ({
        sku: item.product.sku,
        price: item.product.price,
        quantity: item.quantity,
      })),
    };

    return await this.orderRepo.placeOrder(orderInput, token, idempotencyKey);
  }
}

export const placeOrderUseCase = new PlaceOrderUseCase();
