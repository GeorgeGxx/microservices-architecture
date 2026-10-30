import { ApiProperty } from '@nestjs/swagger';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';

export class TrackingEventDto {
  @ApiProperty()
  id: string;

  @ApiProperty({ enum: ShipmentStatus })
  status: ShipmentStatus;

  @ApiProperty()
  location: string;

  @ApiProperty()
  description: string;

  @ApiProperty()
  timestamp: Date;
}

export class ShipmentResponseDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  orderNumber: string;

  @ApiProperty({ enum: ShipmentStatus })
  status: ShipmentStatus;

  @ApiProperty()
  carrier: string;

  @ApiProperty()
  trackingNumber: string;

  @ApiProperty()
  recipientName: string;

  @ApiProperty()
  deliveryAddress: string;

  @ApiProperty({ type: [TrackingEventDto] })
  trackingEvents: TrackingEventDto[];

  @ApiProperty({ required: false })
  dispatchedAt?: Date;

  @ApiProperty({ required: false })
  deliveredAt?: Date;

  @ApiProperty()
  createdAt: Date;
}
