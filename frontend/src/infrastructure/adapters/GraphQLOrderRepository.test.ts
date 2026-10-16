import { describe, expect, it, vi } from 'vitest';
import { GraphQLOrderRepository } from './GraphQLOrderRepository';
import * as graphqlService from '../../services/graphql';
import { Order, PlaceOrderInput } from '../../types';

describe('GraphQLOrderRepository', () => {
  const repo = new GraphQLOrderRepository();

  const mockOrder: Order = {
    id: 'ord-123',
    orderNumber: 'ORD-999',
    customerName: 'Alex Mercer',
    totalAmount: 150,
    orderStatus: 'PLACED',
    orderItems: [],
  };

  it('delegates getOrders to fetchOrders', async () => {
    const spy = vi.spyOn(graphqlService, 'fetchOrders').mockResolvedValue([mockOrder]);

    const result = await repo.getOrders('test-token');

    expect(result).toEqual([mockOrder]);
    expect(spy).toHaveBeenCalledWith('test-token');
    spy.mockRestore();
  });

  it('delegates placeOrder to submitPlaceOrder', async () => {
    const input: PlaceOrderInput = {
      customerName: 'Alex Mercer',
      customerEmail: 'alex@novashop.dev',
      shippingAddress: '123 Main St',
      city: 'Boston',
      postalCode: '02101',
      phone: '+1 555 1234',
      deliveryMethod: 'DHL',
      paymentMethod: 'APPROVED',
      orderItems: [],
    };

    const spy = vi.spyOn(graphqlService, 'submitPlaceOrder').mockResolvedValue(mockOrder);

    const result = await repo.placeOrder(input, 'mock-jwt', 'mock-uuid-1');

    expect(result).toEqual(mockOrder);
    expect(spy).toHaveBeenCalledWith(input, 'mock-jwt', 'mock-uuid-1');
    spy.mockRestore();
  });

  it('delegates cancelOrder to submitCancelOrder', async () => {
    const cancelledOrder: Order = { ...mockOrder, orderStatus: 'CANCELLED' };
    const spy = vi.spyOn(graphqlService, 'submitCancelOrder').mockResolvedValue(cancelledOrder);

    const result = await repo.cancelOrder('ord-123', 'test-token');

    expect(result.orderStatus).toBe('CANCELLED');
    expect(spy).toHaveBeenCalledWith('ord-123', 'test-token');
    spy.mockRestore();
  });
});
