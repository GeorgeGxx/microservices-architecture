import { describe, expect, it, vi } from 'vitest';
import { PlaceOrderUseCase, createIdempotencyKey, PlaceOrderRequest } from './PlaceOrderUseCase';
import { IOrderRepository } from '../../domain/repositories/IOrderRepository';
import { Order, CartItem } from '../../types';

describe('PlaceOrderUseCase', () => {
  const mockOrder: Order = {
    id: 'ord-101',
    orderNumber: 'ORD-2026-001',
    customerName: 'Alex Mercer',
    totalAmount: 199.99,
    orderStatus: 'PLACED',
    orderItems: [],
  };

  const sampleItems: CartItem[] = [
    {
      product: {
        id: 'p1',
        sku: 'LAPTOP-PRO',
        name: 'Laptop Pro 16',
        price: 199.99,
      },
      quantity: 1,
    },
  ];

  const validRequest: PlaceOrderRequest = {
    items: sampleItems,
    customerName: 'Alex Mercer',
    customerEmail: 'alex@novashop.dev',
    shippingAddress: '456 Enterprise Blvd, Suite 200',
    city: 'Seattle',
    postalCode: '98101',
    phone: '+1 555 4321',
    deliveryMethod: 'DHL Priority Express',
    paymentMethod: 'SIMULATED_APPROVED',
  };

  const createMockRepo = (): IOrderRepository => ({
    getOrders: vi.fn().mockResolvedValue([mockOrder]),
    placeOrder: vi.fn().mockResolvedValue(mockOrder),
    cancelOrder: vi.fn().mockResolvedValue({ ...mockOrder, orderStatus: 'CANCELLED' }),
  });

  it('generates a valid UUIDv4 idempotency key', () => {
    const key = createIdempotencyKey();
    expect(key).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  });

  it('successfully places an order through the repository', async () => {
    const repo = createMockRepo();
    const useCase = new PlaceOrderUseCase(repo);

    const result = await useCase.execute(validRequest, 'mock-jwt-token', 'custom-key-123');

    expect(result).toEqual(mockOrder);
    expect(repo.placeOrder).toHaveBeenCalledWith(
      expect.objectContaining({
        customerName: 'Alex Mercer',
        customerEmail: 'alex@novashop.dev',
        shippingAddress: '456 Enterprise Blvd, Suite 200',
        city: 'Seattle',
        postalCode: '98101',
        phone: '+1 555 4321',
        deliveryMethod: 'DHL Priority Express',
        paymentMethod: 'SIMULATED_APPROVED',
      }),
      'mock-jwt-token',
      'custom-key-123'
    );
  });

  it('automatically generates an idempotency key if none is provided', async () => {
    const repo = createMockRepo();
    const useCase = new PlaceOrderUseCase(repo);

    await useCase.execute(validRequest);

    expect(repo.placeOrder).toHaveBeenCalledWith(
      expect.any(Object),
      undefined,
      expect.stringMatching(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i)
    );
  });

  it('throws an error if cart is empty', async () => {
    const repo = createMockRepo();
    const useCase = new PlaceOrderUseCase(repo);

    await expect(useCase.execute({ ...validRequest, items: [] })).rejects.toThrow(
      'Cart cannot be empty to place an order.'
    );
    expect(repo.placeOrder).not.toHaveBeenCalled();
  });

  it('throws an error if email is missing or lacks @ symbol', async () => {
    const repo = createMockRepo();
    const useCase = new PlaceOrderUseCase(repo);

    await expect(useCase.execute({ ...validRequest, customerEmail: '' })).rejects.toThrow(
      'Please provide a valid email address.'
    );
    await expect(useCase.execute({ ...validRequest, customerEmail: 'notanemail' })).rejects.toThrow(
      'Please provide a valid email address.'
    );
    expect(repo.placeOrder).not.toHaveBeenCalled();
  });

  it('throws an error if shipping address is under 5 characters', async () => {
    const repo = createMockRepo();
    const useCase = new PlaceOrderUseCase(repo);

    await expect(useCase.execute({ ...validRequest, shippingAddress: 'abc' })).rejects.toThrow(
      'Shipping address is required and must include street details.'
    );
    expect(repo.placeOrder).not.toHaveBeenCalled();
  });

  it('falls back to crypto.getRandomValues when randomUUID is not available', () => {
    const originalRandomUUID = crypto.randomUUID;
    try {
      Object.defineProperty(crypto, 'randomUUID', { value: undefined, configurable: true });
      const key = createIdempotencyKey();
      expect(key).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
    } finally {
      Object.defineProperty(crypto, 'randomUUID', { value: originalRandomUUID, configurable: true });
    }
  });

  it('exports a default singleton instance', async () => {
    const { placeOrderUseCase } = await import('./PlaceOrderUseCase');
    expect(placeOrderUseCase).toBeInstanceOf(PlaceOrderUseCase);
  });
});


