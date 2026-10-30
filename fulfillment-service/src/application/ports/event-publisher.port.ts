import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentDeliveredEvent } from '../../domain/events/shipment-delivered.event';

export const EVENT_PUBLISHER = 'EVENT_PUBLISHER';

export interface EventPublisher {
  publishDispatched(event: ShipmentDispatchedEvent): Promise<void>;
  publishDelivered(event: ShipmentDeliveredEvent): Promise<void>;
  publishFailed?(orderNumber: string, reason: string): Promise<void>;
}
