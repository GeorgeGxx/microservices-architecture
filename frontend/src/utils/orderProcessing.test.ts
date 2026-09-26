import { describe, it, expect } from 'vitest';
import { processOrders, ProcessOrdersOptions } from './orderProcessing';
import { Order } from '../types';

describe('Order Processing & Pagination (TDD)', () => {
  const mockOrders: Order[] = [
    {
      id: '1',
      orderNumber: 'ORD-001',
      orderStatus: 'DELIVERED',
      totalAmount: 100,
      customerName: 'Alice Johnson',
      trackingNumber: 'DHL-001',
      createdAt: '2026-09-20T10:00:00Z',
      orderItems: [],
    },
    {
      id: '2',
      orderNumber: 'ORD-002',
      orderStatus: 'SHIPPED',
      totalAmount: 200,
      customerName: 'Bob Smith',
      trackingNumber: 'DHL-002',
      createdAt: '2026-09-22T10:00:00Z',
      orderItems: [],
    },
    {
      id: '3',
      orderNumber: 'ORD-003',
      orderStatus: 'PLACED',
      totalAmount: 300,
      customerName: 'Charlie Brown',
      trackingNumber: 'DHL-003',
      createdAt: '2026-09-24T10:00:00Z',
      orderItems: [],
    },
    {
      id: '4',
      orderNumber: 'ORD-004',
      orderStatus: 'CONFIRMED',
      totalAmount: 400,
      customerName: 'Diana Prince',
      trackingNumber: 'DHL-004',
      createdAt: '2026-09-26T10:00:00Z',
      orderItems: [],
    },
    {
      id: '5',
      orderNumber: 'ORD-005',
      orderStatus: 'PLACED',
      totalAmount: 500,
      customerName: 'Edward Norton',
      trackingNumber: 'DHL-005',
      createdAt: '2026-09-26T14:00:00Z',
      orderItems: [],
    },
  ];

  it('Requirement: Invert order so the latest/newest order is first', () => {
    const result = processOrders(mockOrders, { page: 1, pageSize: 10 });
    // The last order in mockOrders was ORD-005 (or newest createdAt). It must be first!
    expect(result.paginatedOrders[0].orderNumber).toBe('ORD-005');
    expect(result.paginatedOrders[1].orderNumber).toBe('ORD-004');
    expect(result.paginatedOrders[2].orderNumber).toBe('ORD-003');
    expect(result.paginatedOrders[3].orderNumber).toBe('ORD-002');
    expect(result.paginatedOrders[4].orderNumber).toBe('ORD-001');
  });

  it('Requirement: Pagination divides inverted list into correct pages', () => {
    // Page 1 with pageSize 2 should return ORD-005 and ORD-004
    const page1 = processOrders(mockOrders, { page: 1, pageSize: 2 });
    expect(page1.paginatedOrders).toHaveLength(2);
    expect(page1.paginatedOrders[0].orderNumber).toBe('ORD-005');
    expect(page1.paginatedOrders[1].orderNumber).toBe('ORD-004');
    expect(page1.totalPages).toBe(3);
    expect(page1.totalOrders).toBe(5);
    expect(page1.startIndex).toBe(1);
    expect(page1.endIndex).toBe(2);

    // Page 2 with pageSize 2 should return ORD-003 and ORD-002
    const page2 = processOrders(mockOrders, { page: 2, pageSize: 2 });
    expect(page2.paginatedOrders).toHaveLength(2);
    expect(page2.paginatedOrders[0].orderNumber).toBe('ORD-003');
    expect(page2.paginatedOrders[1].orderNumber).toBe('ORD-002');
    expect(page2.startIndex).toBe(3);
    expect(page2.endIndex).toBe(4);

    // Page 3 with pageSize 2 should return remaining ORD-001
    const page3 = processOrders(mockOrders, { page: 3, pageSize: 2 });
    expect(page3.paginatedOrders).toHaveLength(1);
    expect(page3.paginatedOrders[0].orderNumber).toBe('ORD-001');
    expect(page3.startIndex).toBe(5);
    expect(page3.endIndex).toBe(5);
  });

  it('Requirement: Search term filters before pagination', () => {
    const result = processOrders(mockOrders, {
      searchTerm: 'charlie',
      page: 1,
      pageSize: 5,
    });
    expect(result.totalOrders).toBe(1);
    expect(result.paginatedOrders[0].orderNumber).toBe('ORD-003');
  });

  it('Requirement: Status filter works alongside search and pagination', () => {
    const result = processOrders(mockOrders, {
      statusFilter: 'PLACED',
      page: 1,
      pageSize: 5,
    });
    // PLACED orders are ORD-003 and ORD-005. Since inverted, ORD-005 must be first!
    expect(result.totalOrders).toBe(2);
    expect(result.paginatedOrders[0].orderNumber).toBe('ORD-005');
    expect(result.paginatedOrders[1].orderNumber).toBe('ORD-003');
  });

  it('Edge case: Empty orders list returns empty pagination safely', () => {
    const result = processOrders([], { page: 1, pageSize: 10 });
    expect(result.paginatedOrders).toEqual([]);
    expect(result.totalOrders).toBe(0);
    expect(result.totalPages).toBe(1);
    expect(result.startIndex).toBe(0);
    expect(result.endIndex).toBe(0);
  });
});
