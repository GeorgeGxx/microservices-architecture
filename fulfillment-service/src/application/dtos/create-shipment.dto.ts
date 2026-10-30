import { ApiProperty } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString, IsArray, ValidateNested, IsNumber, Min } from 'class-validator';
import { Type } from 'class-transformer';

export class PackageItemDto {
  @ApiProperty({ example: 'SKU-LAPTOP-01', description: 'Stock keeping unit identifier' })
  @IsString()
  @IsNotEmpty()
  sku: string;

  @ApiProperty({ example: 1, description: 'Number of items in the package' })
  @IsNumber()
  @Min(1)
  quantity: number;
}

export class CreateShipmentDto {
  @ApiProperty({ example: 'ORD-12345', description: 'Unique order identifier' })
  @IsString()
  @IsNotEmpty()
  orderNumber: string;

  @ApiProperty({ example: 'Alice Smith', description: 'Recipient full name' })
  @IsString()
  @IsNotEmpty()
  recipientName: string;

  @ApiProperty({ example: '123 Market Street', description: 'Delivery street address' })
  @IsString()
  @IsNotEmpty()
  street: string;

  @ApiProperty({ example: 'San Francisco', description: 'City' })
  @IsString()
  @IsNotEmpty()
  city: string;

  @ApiProperty({ example: '94103', description: 'Postal / ZIP code' })
  @IsString()
  @IsNotEmpty()
  postalCode: string;

  @ApiProperty({ example: '+1-555-0199', required: false })
  @IsString()
  @IsOptional()
  phone?: string;

  @ApiProperty({ example: 'DHL Express', default: 'DHL Express', required: false })
  @IsString()
  @IsOptional()
  carrier?: string;

  @ApiProperty({ type: [PackageItemDto], required: false })
  @IsArray()
  @IsOptional()
  @ValidateNested({ each: true })
  @Type(() => PackageItemDto)
  items?: PackageItemDto[];
}
