export type DeliveryStage = 'PLACED' | 'CONFIRMED' | 'PREPARING' | 'SHIPPED' | 'DELIVERED';

export interface StageDefinition {
  id: number;
  key: DeliveryStage;
  label: string;
  shortTitle: string;
  desc: string;
}

export const DELIVERY_STAGES: readonly StageDefinition[] = [
  { id: 1, key: 'PLACED', label: '1. Placed', shortTitle: 'Placed', desc: 'Order Registered' },
  { id: 2, key: 'CONFIRMED', label: '2. Confirmed', shortTitle: 'Confirmed', desc: 'Saga Payment Captured' },
  { id: 3, key: 'PREPARING', label: '3. Warehouse', shortTitle: 'Warehouse', desc: 'Picking & Express Packing' },
  { id: 4, key: 'SHIPPED', label: '4. In Transit', shortTitle: 'In Transit', desc: 'DHL Express Satellite' },
  { id: 5, key: 'DELIVERED', label: '5. Delivered', shortTitle: 'Delivered', desc: 'Signed & Handed Over' },
] as const;

/**
 * Parity rule with Angular 21:
 * An order can ONLY be cancelled when its status is strictly PLACED.
 * Once it reaches CONFIRMED (or downstream stages), cancellation is locked.
 */
export function canCancelOrder(status?: string | null): boolean {
  if (!status) return false;
  return status.trim().toUpperCase() === 'PLACED';
}

/**
 * Returns the numeric index (0 to 4) of a stage in the 5-stage pipeline, or -1 if cancelled/unknown.
 */
export function getDeliveryStageIndex(status?: string | null): number {
  if (!status) return -1;
  const s = status.trim().toUpperCase();
  return DELIVERY_STAGES.findIndex((stage) => stage.key === s);
}

export interface NextStageResult {
  nextStatus: DeliveryStage;
  milestoneTitle: string;
  milestoneMessage: string;
  notificationType: 'order' | 'info';
}

/**
 * Computes next stage progression and rich notification payload for real-time live simulation.
 */
export function getNextDeliveryStage(currentStatus: string, orderNumber?: string): NextStageResult | null {
  const s = currentStatus.trim().toUpperCase();
  const ref = orderNumber ? ` #${orderNumber}` : '';

  switch (s) {
    case 'PLACED':
      return {
        nextStatus: 'CONFIRMED',
        milestoneTitle: `Order${ref} Confirmed!`,
        milestoneMessage: 'Saga payment captured & inventory reserved. Cancellation window is now locked.',
        notificationType: 'order',
      };
    case 'CONFIRMED':
      return {
        nextStatus: 'PREPARING',
        milestoneTitle: `Warehouse Dispatching${ref}`,
        milestoneMessage: 'Regional fulfillment hub is actively picking and precision-packaging your items.',
        notificationType: 'info',
      };
    case 'PREPARING':
      return {
        nextStatus: 'SHIPPED',
        milestoneTitle: `Order${ref} In Transit (DHL Express)`,
        milestoneMessage: 'Dispatched with carrier! Real-time DHL satellite telemetry is tracking your route.',
        notificationType: 'order',
      };
    case 'SHIPPED':
      return {
        nextStatus: 'DELIVERED',
        milestoneTitle: `Order${ref} Delivered!`,
        milestoneMessage: 'Your package has been successfully delivered and signed. Enjoy your purchase!',
        notificationType: 'order',
      };
    default:
      return null;
  }
}

/**
 * Resolves effective status adhering strictly to event-driven rules:
 * 1. If backend status is CANCELLED or simulatedStatus is CANCELLED,
 *    it remains CANCELLED permanently (Saga compensation executed; transit never resumes).
 * 2. Otherwise, returns simulatedStatus if available, falling back to backend status.
 */
export function computeEffectiveStatus(
  backendStatus?: string | null,
  simulatedStatus?: string | null
): string {
  const normBackend = (backendStatus || 'PLACED').trim().toUpperCase();
  const normSim = simulatedStatus ? simulatedStatus.trim().toUpperCase() : null;

  if (normBackend === 'CANCELLED' || normSim === 'CANCELLED') {
    return 'CANCELLED';
  }

  return normSim || normBackend;
}

