import { Controller, Post, Get, Patch, Body, Param, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from '../../application/use-cases/dispatch-shipment.use-case';
import { DeliverShipmentUseCase } from '../../application/use-cases/deliver-shipment.use-case';
import { GetShipmentUseCase } from '../../application/use-cases/get-shipment.use-case';
import { CreateShipmentDto } from '../../application/dtos/create-shipment.dto';
import { DispatchShipmentDto, DeliverShipmentDto } from '../../application/dtos/update-shipment-status.dto';
import { ShipmentResponseDto } from '../../application/dtos/shipment-response.dto';
import { FulfillmentMetricsService } from '../../infrastructure/metrics/fulfillment-metrics.service';

@ApiTags('shipments')
@Controller('api/v1/shipments')
export class ShipmentsController {
  constructor(
    private readonly createShipmentUseCase: CreateShipmentUseCase,
    private readonly dispatchShipmentUseCase: DispatchShipmentUseCase,
    private readonly deliverShipmentUseCase: DeliverShipmentUseCase,
    private readonly getShipmentUseCase: GetShipmentUseCase,
    private readonly metricsService: FulfillmentMetricsService,
  ) {}

  @Post()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Create a new shipment for an order' })
  @ApiResponse({ status: 201, type: ShipmentResponseDto, description: 'Shipment created successfully' })
  async createShipment(@Body() dto: CreateShipmentDto): Promise<ShipmentResponseDto> {
    const shipment = await this.createShipmentUseCase.execute(dto);
    this.metricsService.shipmentsTotal.inc({ status: shipment.status, carrier: shipment.carrier });
    return shipment;
  }

  @Get('order/:orderNumber')
  @ApiOperation({ summary: 'Get shipment tracking details by order number' })
  @ApiResponse({ status: 200, type: ShipmentResponseDto })
  async getByOrderNumber(@Param('orderNumber') orderNumber: string): Promise<ShipmentResponseDto> {
    return this.getShipmentUseCase.executeByOrderNumber(orderNumber);
  }

  @Get('tracking/:trackingNumber')
  @ApiOperation({ summary: 'Get shipment tracking details by tracking number' })
  @ApiResponse({ status: 200, type: ShipmentResponseDto })
  async getByTrackingNumber(@Param('trackingNumber') trackingNumber: string): Promise<ShipmentResponseDto> {
    return this.getShipmentUseCase.executeByTrackingNumber(trackingNumber);
  }

  @Patch('order/:orderNumber/dispatch')
  @ApiOperation({ summary: 'Mark shipment as dispatched from warehouse' })
  @ApiResponse({ status: 200, type: ShipmentResponseDto })
  async dispatchShipment(
    @Param('orderNumber') orderNumber: string,
    @Body() dto: DispatchShipmentDto,
  ): Promise<ShipmentResponseDto> {
    const shipment = await this.dispatchShipmentUseCase.execute(orderNumber, dto?.location);
    this.metricsService.dispatchedTotal.inc();
    return shipment;
  }

  @Patch('order/:orderNumber/deliver')
  @ApiOperation({ summary: 'Mark shipment as delivered to recipient' })
  @ApiResponse({ status: 200, type: ShipmentResponseDto })
  async deliverShipment(
    @Param('orderNumber') orderNumber: string,
    @Body() dto: DeliverShipmentDto,
  ): Promise<ShipmentResponseDto> {
    const shipment = await this.deliverShipmentUseCase.execute(orderNumber, dto?.location);
    this.metricsService.deliveredTotal.inc();
    return shipment;
  }
}
