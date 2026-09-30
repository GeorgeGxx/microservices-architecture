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

/** Sorts most recently created orders first, using the monotonic DB ID when no timestamp is exposed. */
export function sortOrdersNewestFirst(orders: Order[]): Order[] {
  return orders
    .map((order, index) => ({ order, index }))
    .sort(({ order: a, index: indexA }, { order: b, index: indexB }) => {
      const timeA = a.createdAt ? Date.parse(a.createdAt) : Number.NaN;
      const timeB = b.createdAt ? Date.parse(b.createdAt) : Number.NaN;
      if (Number.isFinite(timeA) && Number.isFinite(timeB) && timeA !== timeB) return timeB - timeA;

      try {
        const idA = BigInt(a.id);
        const idB = BigInt(b.id);
        if (idA !== idB) return idA > idB ? -1 : 1;
      } catch {
        const idOrder = b.id.localeCompare(a.id, undefined, { numeric: true });
        if (idOrder !== 0) return idOrder;
      }
      return indexA - indexB;
    })
    .map(({ order }) => order);
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
  const inverted = sortOrdersNewestFirst(orders);

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
