import { Order } from '../types';

export interface ProcessOrdersOptions {
  searchTerm?: string;
  statusFilter?: string;
  page?: number;
  pageSize?: number;
}

export interface ProcessedOrdersResult {
  paginatedOrders: Order[];
  totalOrders: number;
  totalPages: number;
  startIndex: number;
  endIndex: number;
}

/**
 * Pure domain utility to filter, invert (newest order first), and paginate orders.
 */
export function processOrders(
  orders: Order[],
  options: ProcessOrdersOptions = {}
): ProcessedOrdersResult {
  const {
    searchTerm = '',
    statusFilter = 'ALL',
    page = 1,
    pageSize = 5,
  } = options;

  if (!orders || orders.length === 0) {
    return {
      paginatedOrders: [],
      totalOrders: 0,
      totalPages: 1,
      startIndex: 0,
      endIndex: 0,
    };
  }

  // 1. Invert list so the newest/last placed order is first
  // If orders have valid createdAt timestamps, sort descending; otherwise reverse list order
  const inverted = [...orders].sort((a, b) => {
    if (a.createdAt && b.createdAt) {
      const timeA = new Date(a.createdAt).getTime();
      const timeB = new Date(b.createdAt).getTime();
      if (!isNaN(timeA) && !isNaN(timeB)) {
        return timeB - timeA;
      }
    }
    // Fallback: reverse order
    return -1;
  });

  // 2. Filter by search term and status
  const normalizedSearch = searchTerm.trim().toLowerCase();
  const normalizedStatus = statusFilter.toUpperCase();

  const filtered = inverted.filter((order) => {
    const matchesSearch = normalizedSearch
      ? order.orderNumber.toLowerCase().includes(normalizedSearch) ||
        (order.customerName && order.customerName.toLowerCase().includes(normalizedSearch)) ||
        (order.trackingNumber && order.trackingNumber.toLowerCase().includes(normalizedSearch))
      : true;

    const matchesStatus =
      normalizedStatus === 'ALL' ||
      order.orderStatus.toUpperCase() === normalizedStatus;

    return matchesSearch && matchesStatus;
  });

  const totalOrders = filtered.length;
  const safePageSize = Math.max(1, pageSize);
  const totalPages = Math.max(1, Math.ceil(totalOrders / safePageSize));
  const safePage = Math.min(Math.max(1, page), totalPages);

  const startOffset = (safePage - 1) * safePageSize;
  const paginatedOrders = filtered.slice(startOffset, startOffset + safePageSize);

  const startIndex = totalOrders === 0 ? 0 : startOffset + 1;
  const endIndex = Math.min(startOffset + safePageSize, totalOrders);

  return {
    paginatedOrders,
    totalOrders,
    totalPages,
    startIndex,
    endIndex,
  };
}
