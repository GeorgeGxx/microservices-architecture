export const ORDER_FULFILLMENT_STAGES = [
  { status: 'PLACED', title: 'Order placed', detail: 'Order accepted by Orders Service' },
  { status: 'SHIPPED', title: 'In transit', detail: 'Shipment recorded by Orders Service' },
  { status: 'DELIVERED', title: 'Delivered', detail: 'Delivery recorded by Orders Service' },
] as const;

export const ORDER_STATUS_PRESENTATION: Record<string, { label: string; tone: 'amber' | 'blue' | 'emerald' | 'rose' | 'slate' }> = {
  PLACED: { label: 'Placed', tone: 'amber' },
  SHIPPED: { label: 'In Transit', tone: 'blue' },
  DELIVERED: { label: 'Delivered', tone: 'emerald' },
  CANCELLED: { label: 'Cancelled', tone: 'rose' },
};

export function getOrderStatusPresentation(status?: string | null) {
  const normalizedStatus = status?.trim().toUpperCase() || '';
  return ORDER_STATUS_PRESENTATION[normalizedStatus] ?? {
    label: normalizedStatus ? normalizedStatus.replaceAll('_', ' ') : 'Unknown',
    tone: 'slate' as const,
  };
}

export function getOrderFulfillmentStageIndex(status?: string | null): number {
  if (!status) return -1;
  const normalizedStatus = status.trim().toUpperCase();
  return ORDER_FULFILLMENT_STAGES.findIndex((stage) => stage.status === normalizedStatus);
}
