import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ShipmentOrmEntity } from './infrastructure/persistence/entities/shipment.orm-entity';
import { TrackingEventOrmEntity } from './infrastructure/persistence/entities/tracking-event.orm-entity';
import { SHIPMENT_REPOSITORY } from './domain/repositories/shipment.repository.interface';
import { TypeOrmShipmentRepository } from './infrastructure/persistence/repositories/typeorm-shipment.repository';
import { EVENT_PUBLISHER } from './application/ports/event-publisher.port';
import { KafkaEventPublisher } from './infrastructure/kafka/kafka-event.publisher';
import { PaymentEventsConsumer } from './infrastructure/kafka/payment-events.consumer';
import { FulfillmentMetricsService } from './infrastructure/metrics/fulfillment-metrics.service';
import { CreateShipmentUseCase } from './application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from './application/use-cases/dispatch-shipment.use-case';
import { DeliverShipmentUseCase } from './application/use-cases/deliver-shipment.use-case';
import { GetShipmentUseCase } from './application/use-cases/get-shipment.use-case';
import { ShipmentsController } from './presentation/controllers/shipments.controller';
import { HealthController } from './presentation/controllers/health.controller';

@Module({
  imports: [
    TypeOrmModule.forFeature([ShipmentOrmEntity, TrackingEventOrmEntity]),
  ],
  controllers: [ShipmentsController, HealthController],
  providers: [
    {
      provide: SHIPMENT_REPOSITORY,
      useClass: TypeOrmShipmentRepository,
    },
    {
      provide: EVENT_PUBLISHER,
      useClass: KafkaEventPublisher,
    },
    FulfillmentMetricsService,
    CreateShipmentUseCase,
    DispatchShipmentUseCase,
    DeliverShipmentUseCase,
    GetShipmentUseCase,
    PaymentEventsConsumer,
  ],
  exports: [
    CreateShipmentUseCase,
    DispatchShipmentUseCase,
    DeliverShipmentUseCase,
    GetShipmentUseCase,
  ],
})
export class FulfillmentModule {}
