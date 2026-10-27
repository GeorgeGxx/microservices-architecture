import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class DispatchShipmentDto {
  @ApiProperty({ example: 'San Francisco Fulfillment Center', required: false })
  @IsString()
  @IsOptional()
  location?: string;
}

export class DeliverShipmentDto {
  @ApiProperty({ example: 'Front Door / Recipient Signed', required: false })
  @IsString()
  @IsOptional()
  location?: string;
}
