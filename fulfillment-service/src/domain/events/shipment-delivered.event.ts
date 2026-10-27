export class ShipmentDeliveredEvent {
  constructor(
    public readonly shipmentId: string,
    public readonly orderNumber: string,
    public readonly carrier: string,
    public readonly trackingNumber: string,
    public readonly deliveredAt: Date,
  ) {}
}
