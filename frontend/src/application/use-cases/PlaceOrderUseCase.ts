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

export function createIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }

  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  throw new Error('Secure browser cryptography is required to place an order.');
}

export class PlaceOrderUseCase {
  constructor(private readonly orderRepo: IOrderRepository = orderRepository) {}

  async execute(request: PlaceOrderRequest, token?: string, idempotencyKey?: string): Promise<Order> {
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
    const requestKey = idempotencyKey ?? createIdempotencyKey();

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

    return await this.orderRepo.placeOrder(orderInput, token, requestKey);
  }
}

export const placeOrderUseCase = new PlaceOrderUseCase();
