import { Injectable, Inject, NotFoundException } from '@nestjs/common';
import { SHIPMENT_REPOSITORY, ShipmentRepository } from '../../domain/repositories/shipment.repository.interface';
import { EVENT_PUBLISHER, EventPublisher } from '../ports/event-publisher.port';
import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentResponseDto } from '../dtos/shipment-response.dto';
import { CreateShipmentUseCase } from './create-shipment.use-case';

@Injectable()
export class DispatchShipmentUseCase {
  constructor(
    @Inject(SHIPMENT_REPOSITORY)
    private readonly shipmentRepository: ShipmentRepository,
    @Inject(EVENT_PUBLISHER)
    private readonly eventPublisher: EventPublisher,
  ) {}

  async execute(orderNumber: string, location?: string): Promise<ShipmentResponseDto> {
    const shipment = await this.shipmentRepository.findByOrderNumber(orderNumber);
    if (!shipment) {
      throw new NotFoundException(`Shipment for order #${orderNumber} not found`);
    }

    shipment.dispatch(location || 'Distribution Facility');
    const saved = await this.shipmentRepository.save(shipment);

    await this.eventPublisher.publishDispatched(
      new ShipmentDispatchedEvent(
        saved.id,
        saved.orderNumber,
        saved.carrier,
        saved.trackingNumber.getValue(),
        saved.dispatchedAt || new Date(),
      ),
    );

    const helper = new CreateShipmentUseCase(this.shipmentRepository);
    return helper.toResponseDto(saved);
  }
}
