export interface Product {
  id?: string;
  sku: string;
  name: string;
  description?: string;
  price: number;
  status?: boolean;
  imageUrl?: string;
  category?: string;
  rating?: number;
  reviewCount?: number;
  isBestSeller?: boolean;
  // Federated fields from inventory-service:
  quantity?: number;
  isInStock?: boolean;
}

export interface OrderItemInput {
  sku: string;
  price: number;
  quantity: number;
}

export interface OrderLineItem {
  id?: string;
  sku: string;
  price: number;
  quantity: number;
  product?: Product;
}

export interface PlaceOrderInput {
  orderItems: OrderItemInput[];
  customerName?: string;
  customerEmail?: string;
  shippingAddress?: string;
  city?: string;
  postalCode?: string;
  phone?: string;
  deliveryMethod?: string;
  paymentMethod?: string;
}

export interface Order {
  id: string;
  orderNumber: string;
  userId?: string;
  username?: string;
  orderStatus: 'PLACED' | 'CONFIRMED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED' | string;
  orderItems: OrderLineItem[];
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
  createdAt?: string;
}

export interface CartItem {
  product: Product;
  quantity: number;
}

export interface InventoryItem {
  id?: string;
  sku: string;
  quantity: number;
  isInStock: boolean;
}

export interface AppNotification {
  id: string;
  title: string;
  message: string;
  type: 'order' | 'stock' | 'system' | 'info';
  timestamp: Date;
  read: boolean;
  orderNumber?: string;
  userId?: string;
  username?: string;
}

export interface UserProfile {
  userId?: string;
  username: string;
  email?: string;
  firstName?: string;
  lastName?: string;
  roles: string[];
  isAdmin: boolean;
  token?: string;
}
