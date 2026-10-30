import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { FulfillmentModule } from './fulfillment.module';
import { ShipmentOrmEntity } from './infrastructure/persistence/entities/shipment.orm-entity';
import { TrackingEventOrmEntity } from './infrastructure/persistence/entities/tracking-event.orm-entity';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'postgres',
      host: process.env.DB_HOST || 'localhost',
      port: Number.parseInt(process.env.DB_PORT || '5437', 10),
      username: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'admin',
      database: process.env.DB_NAME || 'ms_fulfillment',
      entities: [ShipmentOrmEntity, TrackingEventOrmEntity],
      synchronize: true, // Auto schema sync for PostgreSQL 18
      logging: process.env.NODE_ENV === 'development',
      retryAttempts: 15,
      retryDelay: 2000,
    }),
    FulfillmentModule,
  ],
})
export class AppModule {}
