import { Shipment } from '../models/shipment.entity';

export const SHIPMENT_REPOSITORY = 'SHIPMENT_REPOSITORY';

export interface ShipmentRepository {
  save(shipment: Shipment): Promise<Shipment>;
  findById(id: string): Promise<Shipment | null>;
  findByOrderNumber(orderNumber: string): Promise<Shipment | null>;
  findByTrackingNumber(trackingNumber: string): Promise<Shipment | null>;
}
