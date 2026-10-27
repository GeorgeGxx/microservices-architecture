import { ShipmentMapper } from './shipment.mapper';
import { Shipment } from '../../../domain/models/shipment.entity';
import { ShipmentStatus } from '../../../domain/value-objects/shipment-status.enum';

describe('ShipmentMapper (DDD Infra)', () => {
  it('should map between Domain Aggregate and ORM Entity bidirectionally', () => {
    const domain = Shipment.create({
      orderNumber: 'ORD-MAP-01',
      recipientName: 'Stanley Hudson',
      street: 'Crossword Lane 1',
      city: 'Tampa',
      postalCode: '33601',
      carrier: 'DHL Express',
      items: [{ sku: 'SKU-PEN', quantity: 5 } as any],
    });

    const orm = ShipmentMapper.toOrm(domain);
    expect(orm.orderNumber).toBe('ORD-MAP-01');
    expect(orm.status).toBe(ShipmentStatus.AWAITING_PICKUP);
    expect(orm.items.length).toBe(1);

    const remappedDomain = ShipmentMapper.toDomain(orm);
    expect(remappedDomain.id).toBe(domain.id);
    expect(remappedDomain.orderNumber).toBe(domain.orderNumber);
    expect(remappedDomain.address.recipientName).toBe('Stanley Hudson');
    expect(remappedDomain.trackingNumber.getValue()).toBe(domain.trackingNumber.getValue());
  });
});
