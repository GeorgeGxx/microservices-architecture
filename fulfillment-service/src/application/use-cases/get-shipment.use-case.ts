import { Injectable, Inject, NotFoundException } from '@nestjs/common';
import { SHIPMENT_REPOSITORY, ShipmentRepository } from '../../domain/repositories/shipment.repository.interface';
import { ShipmentResponseDto } from '../dtos/shipment-response.dto';
import { CreateShipmentUseCase } from './create-shipment.use-case';

@Injectable()
export class GetShipmentUseCase {
  constructor(
    @Inject(SHIPMENT_REPOSITORY)
    private readonly shipmentRepository: ShipmentRepository,
  ) {}

  async executeByOrderNumber(orderNumber: string): Promise<ShipmentResponseDto> {
    const shipment = await this.shipmentRepository.findByOrderNumber(orderNumber);
    if (!shipment) {
      throw new NotFoundException(`No shipment found for order #${orderNumber}`);
    }
    const helper = new CreateShipmentUseCase(this.shipmentRepository);
    return helper.toResponseDto(shipment);
  }

  async executeByTrackingNumber(trackingNumber: string): Promise<ShipmentResponseDto> {
    const shipment = await this.shipmentRepository.findByTrackingNumber(trackingNumber);
    if (!shipment) {
      throw new NotFoundException(`No shipment found for tracking number ${trackingNumber}`);
    }
    const helper = new CreateShipmentUseCase(this.shipmentRepository);
    return helper.toResponseDto(shipment);
  }
}
