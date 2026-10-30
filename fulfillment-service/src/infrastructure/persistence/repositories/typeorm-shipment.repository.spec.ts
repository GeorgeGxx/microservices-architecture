import { TypeOrmShipmentRepository } from './typeorm-shipment.repository';
import { ShipmentOrmEntity } from '../entities/shipment.orm-entity';
import { Shipment } from '../../../domain/models/shipment.entity';
import { ShipmentStatus } from '../../../domain/value-objects/shipment-status.enum';

describe('TypeOrmShipmentRepository', () => {
  let repository: TypeOrmShipmentRepository;
  let mockOrmRepo: any;

  beforeEach(() => {
    mockOrmRepo = {
      save: jest.fn(),
      findOne: jest.fn(),
    };
    repository = new TypeOrmShipmentRepository(mockOrmRepo);
  });

  const sampleDomain = Shipment.create({
    orderNumber: 'ORD-REPO-1',
    recipientName: 'Michael Scott',
    street: '1725 Slough Ave',
    city: 'Scranton',
    postalCode: '18503',
  });

  const sampleOrm = new ShipmentOrmEntity();
  sampleOrm.id = sampleDomain.id;
  sampleOrm.orderNumber = 'ORD-REPO-1';
  sampleOrm.status = ShipmentStatus.AWAITING_PICKUP;
  sampleOrm.carrier = 'DHL Express';
  sampleOrm.trackingNumber = sampleDomain.trackingNumber.getValue();
  sampleOrm.recipientName = 'Michael Scott';
  sampleOrm.street = '1725 Slough Ave';
  sampleOrm.city = 'Scranton';
  sampleOrm.postalCode = '18503';
  sampleOrm.phone = '';
  sampleOrm.items = [];
  sampleOrm.trackingEvents = [];
  sampleOrm.createdAt = new Date();
  sampleOrm.updatedAt = new Date();

  it('save should map domain to ORM, call save, and map back', async () => {
    mockOrmRepo.save.mockResolvedValue(sampleOrm);

    const result = await repository.save(sampleDomain);
    expect(mockOrmRepo.save).toHaveBeenCalled();
    expect(result.orderNumber).toBe('ORD-REPO-1');
  });

  it('findById should return domain or null', async () => {
    mockOrmRepo.findOne.mockResolvedValueOnce(sampleOrm);
    const found = await repository.findById(sampleDomain.id);
    expect(found?.id).toBe(sampleDomain.id);

    mockOrmRepo.findOne.mockResolvedValueOnce(null);
    const notFound = await repository.findById('unknown');
    expect(notFound).toBeNull();
  });

  it('findByOrderNumber should return domain or null', async () => {
    mockOrmRepo.findOne.mockResolvedValueOnce(sampleOrm);
    const found = await repository.findByOrderNumber('ORD-REPO-1');
    expect(found?.orderNumber).toBe('ORD-REPO-1');

    mockOrmRepo.findOne.mockResolvedValueOnce(null);
    expect(await repository.findByOrderNumber('none')).toBeNull();
  });

  it('findByTrackingNumber should return domain or null', async () => {
    mockOrmRepo.findOne.mockResolvedValueOnce(sampleOrm);
    const found = await repository.findByTrackingNumber('DHL-12345678');
    expect(found).not.toBeNull();

    mockOrmRepo.findOne.mockResolvedValueOnce(null);
    expect(await repository.findByTrackingNumber('none')).toBeNull();
  });
});
