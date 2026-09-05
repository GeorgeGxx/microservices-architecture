export interface OrderItemRequest {
  sku: string;
  price: number;
  quantity: number;
}

export interface OrderRequest {
  orderItems: OrderItemRequest[];
  customerName?: string;
  customerEmail?: string;
  shippingAddress?: string;
  city?: string;
  postalCode?: string;
  phone?: string;
  deliveryMethod?: 'STANDARD' | 'EXPRESS';
  shippingFee?: number;
  taxAmount?: number;
  totalAmount?: number;
  paymentMethod?: string;
}

export interface OrderItemResponse {
  id?: number;
  sku: string;
  price: number;
  quantity: number;
}

export interface OrderResponse {
  id?: number;
  orderNumber: string;
  userId?: string;
  username?: string;
  orderStatus?: 'PLACED' | 'CANCELLED' | 'SHIPPED' | 'DELIVERED';
  orderItems: OrderItemResponse[];
  customerName?: string;
  customerEmail?: string;
  shippingAddress?: string;
  city?: string;
  postalCode?: string;
  phone?: string;
  deliveryMethod?: string;
  trackingNumber?: string;
  carrier?: string;
  subtotalAmount?: number;
  shippingFee?: number;
  taxAmount?: number;
  totalAmount?: number;
  paymentMethod?: string;
}
