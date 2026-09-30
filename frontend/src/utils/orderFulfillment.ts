export const ORDER_FULFILLMENT_STAGES = [
  { status: 'PLACED', title: 'Order placed', detail: 'Order recorded by Orders Service' },
  { status: 'SHIPPED', title: 'Shipped', detail: 'Dispatch recorded by Orders Service' },
  { status: 'DELIVERED', title: 'Delivered', detail: 'Delivery recorded by Orders Service' },
] as const;

export function getOrderFulfillmentStageIndex(status?: string | null): number {
  if (!status) return -1;
  const normalizedStatus = status.trim().toUpperCase();
  return ORDER_FULFILLMENT_STAGES.findIndex((stage) => stage.status === normalizedStatus);
}
