export class ShipmentDispatchedEvent {
  constructor(
    public readonly shipmentId: string,
    public readonly orderNumber: string,
    public readonly carrier: string,
    public readonly trackingNumber: string,
    public readonly dispatchedAt: Date,
  ) {}
}
