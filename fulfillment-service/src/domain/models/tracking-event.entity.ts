import { v4 as uuidv4 } from 'uuid';
import { ShipmentStatus } from '../value-objects/shipment-status.enum';

export class TrackingEvent {
  public readonly id: string;
  public readonly status: ShipmentStatus;
  public readonly location: string;
  public readonly description: string;
  public readonly timestamp: Date;

  constructor(
    status: ShipmentStatus,
    location: string,
    description: string,
    id?: string,
    timestamp?: Date,
  ) {
    this.id = id || uuidv4();
    this.status = status;
    this.location = location || 'Warehouse Facility';
    this.description = description;
    this.timestamp = timestamp || new Date();
  }
}
