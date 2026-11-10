/**
 * Formal CloudEvents 1.0 Specification Contract & Strongly-Typed Domain Event Payloads.
 * Complies with CNCF CloudEvents v1.0 and centralized schema contracts in contracts/events/.
 */

export interface CloudEvent<T = Record<string, unknown>> {
  specversion: '1.0';
  id: string;
  source: string;
  type: string;
  time?: string;
  datacontenttype?: string;
  dataschema?: string;
  subject?: string;
  data: T;
}

export type OrderStatus =
  | 'PLACED'
  | 'PENDING_PAYMENT'
  | 'CONFIRMED'
  | 'PROCESSING'
  | 'SHIPPED'
  | 'DELIVERED'
  | 'CANCELLED';

export interface OrderItemContract {
  sku: string;
  name?: string;
  quantity: number;
  unitPrice?: number;
  totalPrice?: number;
}

export interface OrderEventContract {
  orderNumber: string;
  orderStatus: OrderStatus | string;
  itemsCount?: number;
  totalAmount?: number;
  customerName?: string;
  customerEmail?: string;
  shippingAddress?: string;
  city?: string;
  postalCode?: string;
  phone?: string;
  deliveryMethod?: string;
  paymentMethod?: string;
  trackingNumber?: string;
  userId?: string;
  items?: OrderItemContract[];
}

export type PaymentEventType =
  | 'PAYMENT_COMPLETED'
  | 'PAYMENT_FAILED'
  | 'PAYMENT_REFUNDED'
  | 'PAYMENT_PENDING';

export type PaymentStatus = 'COMPLETED' | 'FAILED' | 'REFUNDED' | 'PENDING';

export interface PaymentEventContract {
  event_type: PaymentEventType | string;
  status: PaymentStatus | string;
  order_number: string;
  payment_id?: string;
  amount?: number;
  currency?: string;
  payment_method?: string;
  transaction_ref?: string;
  reason?: string;
  error_code?: string;
  customer_name?: string;
  customer_email?: string;
  shipping_address?: string;
  city?: string;
  postal_code?: string;
  phone?: string;
  delivery_method?: string;
  user_id?: string;
  items_count?: number;
  timestamp?: string;
}

export type FulfillmentEventType =
  | 'SHIPMENT_DISPATCHED'
  | 'SHIPMENT_DELIVERED'
  | 'SHIPMENT_FAILED';

export interface FulfillmentEventContract {
  eventType: FulfillmentEventType | string;
  orderNumber: string;
  shipmentId?: string;
  carrier?: string;
  trackingNumber?: string;
  dispatchedAt?: string;
  deliveredAt?: string;
  failedAt?: string;
  reason?: string;
}

/**
 * Unpacks CloudEvents 1.0 envelope or flat JSON message with backwards-compatibility.
 */
export function parseCloudEvent<T extends Record<string, any>>(raw: unknown): {
  id?: string;
  eventType: string;
  data: T;
} {
  if (!raw || typeof raw !== 'object') {
    return { eventType: 'UNKNOWN', data: {} as T };
  }

  const obj = raw as Record<string, any>;

  // Check if it's a CloudEvents 1.0 envelope
  if (obj.specversion === '1.0' && obj.data && typeof obj.data === 'object') {
    return {
      id: typeof obj.id === 'string' ? obj.id : undefined,
      eventType: String(obj.type || 'UNKNOWN'),
      data: obj.data as T,
    };
  }

  // Flat schema compatibility fallback
  const resolvedType = String(
    obj.eventType || obj.event_type || obj.orderStatus || obj.status || 'UNKNOWN',
  );

  return {
    id: typeof obj.id === 'string' ? obj.id : undefined,
    eventType: resolvedType,
    data: obj as T,
  };
}
