import { v4 as uuidv4 } from 'uuid';
import { ShipmentStatus } from '../value-objects/shipment-status.enum';
import { TrackingNumber } from '../value-objects/tracking-number.vo';
import { ShippingAddress } from '../value-objects/shipping-address.vo';
import { PackageItem } from './package-item.vo';
import { TrackingEvent } from './tracking-event.entity';

export interface CreateShipmentProps {
  orderNumber: string;
  recipientName: string;
  street: string;
  city: string;
  postalCode: string;
  phone?: string;
  carrier?: string;
  items?: PackageItem[];
  id?: string;
}

export interface ShipmentProps {
  id?: string;
  orderNumber: string;
  status: ShipmentStatus;
  carrier: string;
  trackingNumber: TrackingNumber;
  address: ShippingAddress;
  items?: PackageItem[];
  trackingEvents?: TrackingEvent[];
  createdAt?: Date;
  updatedAt?: Date;
  dispatchedAt?: Date;
  deliveredAt?: Date;
}

export class Shipment {
  private readonly _id: string;
  private readonly _orderNumber: string;
  private _status: ShipmentStatus;
  private readonly _carrier: string;
  private readonly _trackingNumber: TrackingNumber;
  private readonly _address: ShippingAddress;
  private readonly _items: PackageItem[];
  private readonly _trackingEvents: TrackingEvent[];
  private _dispatchedAt?: Date;
  private _deliveredAt?: Date;
  private readonly _createdAt: Date;
  private _updatedAt: Date;

  constructor(props: ShipmentProps) {
    if (!props.orderNumber || props.orderNumber.trim().length === 0) {
      throw new Error('Order number cannot be empty');
    }
    this._id = props.id || uuidv4();
    this._orderNumber = props.orderNumber;
    this._status = props.status;
    this._carrier = props.carrier || 'DHL Express';
    this._trackingNumber = props.trackingNumber;
    this._address = props.address;
    this._items = props.items || [];
    this._trackingEvents = props.trackingEvents || [];
    this._createdAt = props.createdAt || new Date();
    this._updatedAt = props.updatedAt || new Date();
    this._dispatchedAt = props.dispatchedAt;
    this._deliveredAt = props.deliveredAt;
  }

  public static create(props: CreateShipmentProps): Shipment {
    const address = new ShippingAddress(
      props.recipientName,
      props.street,
      props.city,
      props.postalCode,
      props.phone,
    );
    const carrier = props.carrier || 'DHL Express';
    const trackingNumber = TrackingNumber.generate(carrier);
    const initialEvent = new TrackingEvent(
      ShipmentStatus.AWAITING_PICKUP,
      'Central Fulfillment Hub',
      'Shipment created and awaiting warehouse courier pickup',
    );

    return new Shipment({
      id: props.id || uuidv4(),
      orderNumber: props.orderNumber,
      status: ShipmentStatus.AWAITING_PICKUP,
      carrier,
      trackingNumber,
      address,
      items: props.items || [],
      trackingEvents: [initialEvent],
    });
  }

  public dispatch(location = 'Distribution Center'): void {
    if (this._status === ShipmentStatus.DELIVERED) {
      throw new Error('Cannot dispatch an already delivered shipment');
    }
    if (this._status === ShipmentStatus.CANCELLED) {
      throw new Error('Cannot dispatch a cancelled shipment');
    }

    this._status = ShipmentStatus.DISPATCHED;
    this._dispatchedAt = new Date();
    this._updatedAt = new Date();
    this._trackingEvents.push(
      new TrackingEvent(
        ShipmentStatus.DISPATCHED,
        location,
        `Package dispatched from ${location} via ${this._carrier}`,
      ),
    );
  }

  public markInTransit(location: string): void {
    if (this._status !== ShipmentStatus.DISPATCHED && this._status !== ShipmentStatus.IN_TRANSIT) {
      throw new Error(`Cannot mark in-transit from status ${this._status}`);
    }

    this._status = ShipmentStatus.IN_TRANSIT;
    this._updatedAt = new Date();
    this._trackingEvents.push(
      new TrackingEvent(
        ShipmentStatus.IN_TRANSIT,
        location,
        `Package in transit through ${location}`,
      ),
    );
  }

  public deliver(location = 'Destination Address'): void {
    if (this._status === ShipmentStatus.DELIVERED) {
      return; // Idempotent delivery
    }
    if (this._status === ShipmentStatus.CANCELLED) {
      throw new Error('Cannot deliver a cancelled shipment');
    }

    this._status = ShipmentStatus.DELIVERED;
    this._deliveredAt = new Date();
    this._updatedAt = new Date();
    this._trackingEvents.push(
      new TrackingEvent(
        ShipmentStatus.DELIVERED,
        location,
        `Package successfully delivered to recipient`,
      ),
    );
  }

  public cancel(reason: string): void {
    if (this._status === ShipmentStatus.DELIVERED) {
      throw new Error('Cannot cancel an already delivered shipment');
    }

    this._status = ShipmentStatus.CANCELLED;
    this._updatedAt = new Date();
    this._trackingEvents.push(
      new TrackingEvent(
        ShipmentStatus.CANCELLED,
        'Logistics Operations',
        `Shipment cancelled: ${reason || 'Customer request'}`,
      ),
    );
  }

  // Getters
  public get id(): string { return this._id; }
  public get orderNumber(): string { return this._orderNumber; }
  public get status(): ShipmentStatus { return this._status; }
  public get carrier(): string { return this._carrier; }
  public get trackingNumber(): TrackingNumber { return this._trackingNumber; }
  public get address(): ShippingAddress { return this._address; }
  public get items(): PackageItem[] { return [...this._items]; }
  public get trackingEvents(): TrackingEvent[] { return [...this._trackingEvents]; }
  public get dispatchedAt(): Date | undefined { return this._dispatchedAt; }
  public get deliveredAt(): Date | undefined { return this._deliveredAt; }
  public get createdAt(): Date { return this._createdAt; }
  public get updatedAt(): Date { return this._updatedAt; }
}
