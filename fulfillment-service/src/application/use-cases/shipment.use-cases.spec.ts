import { CreateShipmentUseCase } from './create-shipment.use-case';
import { DispatchShipmentUseCase } from './dispatch-shipment.use-case';
import { DeliverShipmentUseCase } from './deliver-shipment.use-case';
import { GetShipmentUseCase } from './get-shipment.use-case';
import { ShipmentRepository } from '../../domain/repositories/shipment.repository.interface';
import { EventPublisher } from '../ports/event-publisher.port';
import { Shipment } from '../../domain/models/shipment.entity';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';
import { NotFoundException } from '@nestjs/common';

class MockShipmentRepository implements ShipmentRepository {
  public shipments = new Map<string, Shipment>();

  async save(shipment: Shipment): Promise<Shipment> {
    this.shipments.set(shipment.orderNumber, shipment);
    this.shipments.set(shipment.id, shipment);
    this.shipments.set(shipment.trackingNumber.getValue(), shipment);
    return shipment;
  }

  async findById(id: string): Promise<Shipment | null> {
    return this.shipments.get(id) || null;
  }

  async findByOrderNumber(orderNumber: string): Promise<Shipment | null> {
    return this.shipments.get(orderNumber) || null;
  }

  async findByTrackingNumber(trackingNumber: string): Promise<Shipment | null> {
    return this.shipments.get(trackingNumber) || null;
  }
}

class MockEventPublisher implements EventPublisher {
  public dispatchedEvents: any[] = [];
  public deliveredEvents: any[] = [];

  async publishDispatched(event: any): Promise<void> {
    this.dispatchedEvents.push(event);
  }

  async publishDelivered(event: any): Promise<void> {
    this.deliveredEvents.push(event);
  }
}

describe('Fulfillment Application Use Cases', () => {
  let repo: MockShipmentRepository;
  let publisher: MockEventPublisher;
  let createUseCase: CreateShipmentUseCase;
  let dispatchUseCase: DispatchShipmentUseCase;
  let deliverUseCase: DeliverShipmentUseCase;
  let getUseCase: GetShipmentUseCase;

  beforeEach(() => {
    repo = new MockShipmentRepository();
    publisher = new MockEventPublisher();
    createUseCase = new CreateShipmentUseCase(repo);
    dispatchUseCase = new DispatchShipmentUseCase(repo, publisher);
    deliverUseCase = new DeliverShipmentUseCase(repo, publisher);
    getUseCase = new GetShipmentUseCase(repo);
  });

  it('should create a shipment idempotently', async () => {
    const dto = {
      orderNumber: 'ORD-UC-01',
      recipientName: 'Bob Vance',
      street: '100 Refrigeration Way',
      city: 'Scranton',
      postalCode: '18503',
      carrier: 'DHL Express',
      items: [{ sku: 'SKU-COOL-01', quantity: 2 }],
    };

    const res1 = await createUseCase.execute(dto);
    expect(res1.orderNumber).toBe('ORD-UC-01');
    expect(res1.status).toBe(ShipmentStatus.AWAITING_PICKUP);

    // Second call with same orderNumber returns cached shipment
    const res2 = await createUseCase.execute(dto);
    expect(res2.id).toBe(res1.id);
  });

  it('should dispatch shipment and publish event', async () => {
    await createUseCase.execute({
      orderNumber: 'ORD-DISPATCH-01',
      recipientName: 'Dwight Schrute',
      street: 'Beet Farm',
      city: 'Honesdale',
      postalCode: '18431',
    });

    const res = await dispatchUseCase.execute('ORD-DISPATCH-01', 'Scranton Depot');
    expect(res.status).toBe(ShipmentStatus.DISPATCHED);
    expect(publisher.dispatchedEvents).toHaveLength(1);
    expect(publisher.dispatchedEvents[0].orderNumber).toBe('ORD-DISPATCH-01');
  });

  it('should deliver shipment and publish event', async () => {
    await createUseCase.execute({
      orderNumber: 'ORD-DELIVER-01',
      recipientName: 'Jim Halpert',
      street: '42 Elm St',
      city: 'Scranton',
      postalCode: '18503',
    });
    await dispatchUseCase.execute('ORD-DELIVER-01');

    const res = await deliverUseCase.execute('ORD-DELIVER-01', 'Front Door');
    expect(res.status).toBe(ShipmentStatus.DELIVERED);
    expect(publisher.deliveredEvents).toHaveLength(1);
    expect(publisher.deliveredEvents[0].orderNumber).toBe('ORD-DELIVER-01');
  });

  it('should throw NotFoundException when dispatching/delivering unknown order', async () => {
    await expect(dispatchUseCase.execute('UNKNOWN-ORDER')).rejects.toThrow(NotFoundException);
    await expect(deliverUseCase.execute('UNKNOWN-ORDER')).rejects.toThrow(NotFoundException);
  });

  it('should query shipment by order number and tracking number', async () => {
    const created = await createUseCase.execute({
      orderNumber: 'ORD-QUERY-01',
      recipientName: 'Michael Scott',
      street: 'Condo 12',
      city: 'Scranton',
      postalCode: '18503',
    });

    const byOrder = await getUseCase.executeByOrderNumber('ORD-QUERY-01');
    expect(byOrder.id).toBe(created.id);

    const byTracking = await getUseCase.executeByTrackingNumber(created.trackingNumber);
    expect(byTracking.id).toBe(created.id);

    await expect(getUseCase.executeByOrderNumber('NOT-FOUND')).rejects.toThrow(NotFoundException);
    await expect(getUseCase.executeByTrackingNumber('NOT-FOUND')).rejects.toThrow(NotFoundException);
  });
});
