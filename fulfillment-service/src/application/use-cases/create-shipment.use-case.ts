import { Injectable, Inject, ConflictException } from '@nestjs/common';
import { SHIPMENT_REPOSITORY, ShipmentRepository } from '../../domain/repositories/shipment.repository.interface';
import { Shipment } from '../../domain/models/shipment.entity';
import { PackageItem } from '../../domain/models/package-item.vo';
import { CreateShipmentDto } from '../dtos/create-shipment.dto';
import { ShipmentResponseDto } from '../dtos/shipment-response.dto';

@Injectable()
export class CreateShipmentUseCase {
  constructor(
    @Inject(SHIPMENT_REPOSITORY)
    private readonly shipmentRepository: ShipmentRepository,
  ) {}

  async execute(dto: CreateShipmentDto): Promise<ShipmentResponseDto> {
    const existing = await this.shipmentRepository.findByOrderNumber(dto.orderNumber);
    if (existing) {
      // Idempotent: return existing shipment
      return this.toResponseDto(existing);
    }

    const items = dto.items?.map(i => new PackageItem(i.sku, i.quantity)) || [];

    const shipment = Shipment.create({
      orderNumber: dto.orderNumber,
      recipientName: dto.recipientName,
      street: dto.street,
      city: dto.city,
      postalCode: dto.postalCode,
      phone: dto.phone,
      carrier: dto.carrier,
      items,
    });

    const saved = await this.shipmentRepository.save(shipment);
    return this.toResponseDto(saved);
  }

  public toResponseDto(shipment: Shipment): ShipmentResponseDto {
    return {
      id: shipment.id,
      orderNumber: shipment.orderNumber,
      status: shipment.status,
      carrier: shipment.carrier,
      trackingNumber: shipment.trackingNumber.getValue(),
      recipientName: shipment.address.recipientName,
      deliveryAddress: shipment.address.getFullAddress(),
      dispatchedAt: shipment.dispatchedAt,
      deliveredAt: shipment.deliveredAt,
      createdAt: shipment.createdAt,
      trackingEvents: shipment.trackingEvents.map(e => ({
        id: e.id,
        status: e.status,
        location: e.location,
        description: e.description,
        timestamp: e.timestamp,
      })),
    };
  }
}
