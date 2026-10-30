import { Shipment } from './shipment.entity';
import { ShipmentStatus } from '../value-objects/shipment-status.enum';

describe('Shipment Aggregate Root (DDD)', () => {
  const validProps = {
    orderNumber: 'ORD-TEST-001',
    recipientName: 'Jane Doe',
    street: '456 Oak Avenue',
    city: 'Seattle',
    postalCode: '98101',
    phone: '+1-555-1234',
    carrier: 'DHL Express',
  };

  it('should create a shipment in AWAITING_PICKUP status with initial tracking event', () => {
    const shipment = Shipment.create(validProps);

    expect(shipment.id).toBeDefined();
    expect(shipment.orderNumber).toBe(validProps.orderNumber);
    expect(shipment.status).toBe(ShipmentStatus.AWAITING_PICKUP);
    expect(shipment.carrier).toBe('DHL Express');
    expect(shipment.trackingNumber.getValue()).toMatch(/^DHL-[A-Z0-9]{8}$/);
    expect(shipment.address.recipientName).toBe('Jane Doe');
    expect(shipment.trackingEvents).toHaveLength(1);
    expect(shipment.trackingEvents[0].status).toBe(ShipmentStatus.AWAITING_PICKUP);
  });

  it('should throw an error if created with empty order number', () => {
    expect(() => Shipment.create({ ...validProps, orderNumber: '' })).toThrow(
      'Order number cannot be empty',
    );
  });

  it('should transition through lifecycle: dispatch -> markInTransit -> deliver', () => {
    const shipment = Shipment.create(validProps);

    shipment.dispatch('Seattle Warehouse');
    expect(shipment.status).toBe(ShipmentStatus.DISPATCHED);
    expect(shipment.dispatchedAt).toBeDefined();
    expect(shipment.trackingEvents).toHaveLength(2);

    shipment.markInTransit('Denver Sorting Facility');
    expect(shipment.status).toBe(ShipmentStatus.IN_TRANSIT);
    expect(shipment.trackingEvents).toHaveLength(3);

    shipment.deliver('Front Porch');
    expect(shipment.status).toBe(ShipmentStatus.DELIVERED);
    expect(shipment.deliveredAt).toBeDefined();
    expect(shipment.trackingEvents).toHaveLength(4);
  });

  it('should reject invalid state transitions', () => {
    const shipment = Shipment.create(validProps);
    shipment.dispatch();
    shipment.deliver();

    // Cannot dispatch an already delivered shipment
    expect(() => shipment.dispatch()).toThrow('Cannot dispatch an already delivered shipment');
    // Cannot cancel an already delivered shipment
    expect(() => shipment.cancel('Customer changed mind')).toThrow(
      'Cannot cancel an already delivered shipment',
    );
  });

  it('should support cancellation before delivery', () => {
    const shipment = Shipment.create(validProps);
    shipment.cancel('Out of stock items');

    expect(shipment.status).toBe(ShipmentStatus.CANCELLED);
    expect(() => shipment.dispatch()).toThrow('Cannot dispatch a cancelled shipment');
    expect(() => shipment.deliver()).toThrow('Cannot deliver a cancelled shipment');
  });
});
