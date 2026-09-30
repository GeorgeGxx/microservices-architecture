export type PersistedOrderStatus = 'PLACED' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED';

const ORDER_STATUS_COPY: Record<PersistedOrderStatus, { title: string; message: (orderNumber: string) => string }> = {
  PLACED: { title: 'Order placed', message: (number) => `Order #${number} was placed successfully.` },
  SHIPPED: { title: 'Order in transit', message: (number) => `Order #${number} is now in transit.` },
  DELIVERED: { title: 'Order delivered', message: (number) => `Order #${number} has been delivered.` },
  CANCELLED: { title: 'Order cancelled', message: (number) => `Order #${number} was cancelled.` },
};

export function getOrderStatusNotificationCopy(status: PersistedOrderStatus, orderNumber: string) {
  const copy = ORDER_STATUS_COPY[status];
  return { title: copy.title, message: copy.message(orderNumber) };
}
