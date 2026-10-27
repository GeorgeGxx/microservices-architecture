import { Shipment } from '../../../domain/models/shipment.entity';
import { TrackingNumber } from '../../../domain/value-objects/tracking-number.vo';
import { ShippingAddress } from '../../../domain/value-objects/shipping-address.vo';
import { PackageItem } from '../../../domain/models/package-item.vo';
import { TrackingEvent } from '../../../domain/models/tracking-event.entity';
import { ShipmentOrmEntity } from '../entities/shipment.orm-entity';
import { TrackingEventOrmEntity } from '../entities/tracking-event.orm-entity';

export class ShipmentMapper {
  public static toDomain(orm: ShipmentOrmEntity): Shipment {
    const address = new ShippingAddress(
      orm.recipientName,
      orm.street,
      orm.city,
      orm.postalCode,
      orm.phone,
    );

    const trackingNumber = new TrackingNumber(orm.trackingNumber);

    const items = orm.items?.map(i => new PackageItem(i.sku, i.quantity)) || [];

    const trackingEvents = orm.trackingEvents?.map(
      e => new TrackingEvent(e.status, e.location, e.description, e.id, e.timestamp),
    ) || [];

    return new Shipment(
      orm.id,
      orm.orderNumber,
      orm.status,
      orm.carrier,
      trackingNumber,
      address,
      items,
      trackingEvents,
      orm.createdAt,
      orm.updatedAt,
      orm.dispatchedAt,
      orm.deliveredAt,
    );
  }

  public static toOrm(domain: Shipment): ShipmentOrmEntity {
    const orm = new ShipmentOrmEntity();
    orm.id = domain.id;
    orm.orderNumber = domain.orderNumber;
    orm.status = domain.status;
    orm.carrier = domain.carrier;
    orm.trackingNumber = domain.trackingNumber.getValue();
    orm.recipientName = domain.address.recipientName;
    orm.street = domain.address.street;
    orm.city = domain.address.city;
    orm.postalCode = domain.address.postalCode;
    orm.phone = domain.address.phone || '';
    orm.items = domain.items.map(i => ({ sku: i.sku, quantity: i.quantity }));
    orm.dispatchedAt = domain.dispatchedAt;
    orm.deliveredAt = domain.deliveredAt;
    orm.createdAt = domain.createdAt;
    orm.updatedAt = domain.updatedAt;

    orm.trackingEvents = domain.trackingEvents.map(e => {
      const eventOrm = new TrackingEventOrmEntity();
      eventOrm.id = e.id;
      eventOrm.shipmentId = domain.id;
      eventOrm.status = e.status;
      eventOrm.location = e.location;
      eventOrm.description = e.description;
      eventOrm.timestamp = e.timestamp;
      return eventOrm;
    });

    return orm;
  }
}
