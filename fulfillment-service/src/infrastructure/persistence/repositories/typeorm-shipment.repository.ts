import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ShipmentRepository } from '../../../domain/repositories/shipment.repository.interface';
import { Shipment } from '../../../domain/models/shipment.entity';
import { ShipmentOrmEntity } from '../entities/shipment.orm-entity';
import { ShipmentMapper } from '../mappers/shipment.mapper';

@Injectable()
export class TypeOrmShipmentRepository implements ShipmentRepository {
  constructor(
    @InjectRepository(ShipmentOrmEntity)
    private readonly ormRepository: Repository<ShipmentOrmEntity>,
  ) {}

  async save(shipment: Shipment): Promise<Shipment> {
    const ormEntity = ShipmentMapper.toOrm(shipment);
    const saved = await this.ormRepository.save(ormEntity);
    return ShipmentMapper.toDomain(saved);
  }

  async findById(id: string): Promise<Shipment | null> {
    const orm = await this.ormRepository.findOne({
      where: { id },
      relations: { trackingEvents: true },
    });
    return orm ? ShipmentMapper.toDomain(orm) : null;
  }

  async findByOrderNumber(orderNumber: string): Promise<Shipment | null> {
    const orm = await this.ormRepository.findOne({
      where: { orderNumber },
      relations: { trackingEvents: true },
    });
    return orm ? ShipmentMapper.toDomain(orm) : null;
  }

  async findByTrackingNumber(trackingNumber: string): Promise<Shipment | null> {
    const orm = await this.ormRepository.findOne({
      where: { trackingNumber },
      relations: { trackingEvents: true },
    });
    return orm ? ShipmentMapper.toDomain(orm) : null;
  }
}
