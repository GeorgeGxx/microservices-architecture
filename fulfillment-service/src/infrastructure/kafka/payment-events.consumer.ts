import { Injectable, OnModuleInit, OnModuleDestroy, Logger, Optional, Inject } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Kafka, Consumer, CompressionTypes, CompressionCodecs } from 'kafkajs';
import SnappyCodec from 'kafkajs-snappy';
CompressionCodecs[CompressionTypes.Snappy] = SnappyCodec;

import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from '../../application/use-cases/dispatch-shipment.use-case';
import { EVENT_PUBLISHER } from '../../application/ports/event-publisher.port';
import type { EventPublisher } from '../../application/ports/event-publisher.port';
import { FulfillmentMetricsService } from '../metrics/fulfillment-metrics.service';
import { ShipmentOrmEntity } from '../persistence/entities/shipment.orm-entity';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';
import { extractErrorMessage } from '../utils/error.util';

@Injectable()
export class PaymentEventsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PaymentEventsConsumer.name);
  private readonly kafka: Kafka;
  private readonly consumer: Consumer;
  private readonly paymentsTopic = process.env.KAFKA_PAYMENTS_TOPIC || 'payments-topic';
  private readonly ordersTopic = process.env.KAFKA_ORDERS_TOPIC || 'orders-topic';
  private isShuttingDown = false;
  private reconnectTimer?: ReturnType<typeof setTimeout>;

  constructor(
    private readonly createShipmentUseCase: CreateShipmentUseCase,
    @Optional() private readonly dispatchShipmentUseCase?: DispatchShipmentUseCase,
    @Optional() @Inject(EVENT_PUBLISHER) private readonly eventPublisher?: EventPublisher,
    @Optional() private readonly metricsService?: FulfillmentMetricsService,
    @Optional()
    @InjectRepository(ShipmentOrmEntity)
    private readonly shipmentRepo?: Repository<ShipmentOrmEntity>,
  ) {
    const brokers = (process.env.KAFKA_BOOTSTRAP_SERVERS || process.env.KAFKA_BROKERS || 'localhost:9092').split(',');
    this.kafka = new Kafka({
      clientId: 'fulfillment-service-consumer',
      brokers,
      retry: {
        initialRetryTime: 500,
        retries: 15,
      },
    });
    this.consumer = this.kafka.consumer({
      groupId: process.env.KAFKA_GROUP_ID || process.env.KAFKA_CONSUMER_GROUP || 'fulfillment-service-group',
    });
  }

  async onModuleInit() {
    await this.connectAndSubscribe();
  }

  private async connectAndSubscribe() {
    if (this.isShuttingDown) return;
    try {
      await this.consumer.connect();
      await this.consumer.subscribe({
        topics: [this.paymentsTopic, this.ordersTopic],
        fromBeginning: true,
      });
      this.logger.log(`Subscribed to topics: ${this.paymentsTopic}, ${this.ordersTopic}`);

      await this.consumer.run({
        eachMessage: async ({ topic, message }) => {
          if (!message.value) return;
          try {
            const raw = JSON.parse(message.value.toString());
            if (topic === this.ordersTopic) {
              await this.handleOrderEvent(raw);
            } else {
              await this.handlePaymentEvent(raw);
            }
          } catch (err: unknown) {
            const message = extractErrorMessage(err);
            this.logger.error(`Error processing Kafka event on topic ${topic}: ${message}`);
          }
        },
      });
    } catch (err: unknown) {
      const message = extractErrorMessage(err);
      this.logger.warn(`Could not connect Kafka consumer immediately: ${message}. Retrying in 5s...`);
      if (!this.isShuttingDown) {
        this.reconnectTimer = setTimeout(() => {
          void this.connectAndSubscribe();
        }, 5000);
        this.reconnectTimer.unref?.();
      }
    }
  }

  private isNegativePaymentEvent(raw: Record<string, any>): boolean {
    const eventType = raw.event_type || raw.eventType;
    const status = raw.status || raw.paymentStatus;
    return (
      eventType === 'PAYMENT_FAILED' ||
      eventType === 'PAYMENT_REFUNDED' ||
      status === 'FAILED' ||
      status === 'REFUNDED' ||
      Boolean(raw.error_code)
    );
  }

  private resolveCarrier(rawMethod?: unknown): string {
    if (typeof rawMethod === 'string') {
      if (rawMethod.includes('FedEx')) {
        return 'FedEx';
      }
      if (rawMethod.includes('DHL')) {
        return 'DHL Express';
      }
      return rawMethod;
    }
    return 'DHL Express';
  }

  private async handlePaymentEvent(raw: Record<string, any>): Promise<void> {
    const orderNumber = raw.order_number || raw.orderNumber;
    if (!orderNumber || this.isNegativePaymentEvent(raw)) {
      return;
    }

    const streetVal = raw.shipping_address || raw.street;
    const street = typeof streetVal === 'string' ? streetVal : '100 Main St';
    if (street.includes('FAIL_SHIPMENT')) {
      const reason = 'Undeliverable shipping address rejected by carrier validation';
      this.logger.warn(`Fulfillment validation failed for order #${orderNumber}: ${reason}`);
      if (this.eventPublisher?.publishFailed) {
        await this.eventPublisher.publishFailed(orderNumber, reason);
      }
      return;
    }

    const carrier = this.resolveCarrier(raw.delivery_method || raw.deliveryMethod || raw.carrier);

    this.logger.log(`Received PaymentCompleted for order #${orderNumber}, creating shipment via ${carrier}...`);
    const created = await this.createShipmentUseCase.execute({
      orderNumber,
      recipientName: raw.customer_name || raw.recipientName || 'Customer',
      street,
      city: raw.city || 'Metropolis',
      postalCode: raw.postal_code || raw.postalCode || '10001',
      phone: raw.phone,
      carrier,
    });

    if (this.metricsService && created) {
      this.metricsService.shipmentsTotal.inc({ status: created.status, carrier: created.carrier });
    }

    if (this.dispatchShipmentUseCase && process.env.AUTO_DISPATCH_SHIPMENT === 'true') {
      await this.dispatchShipmentUseCase.execute(orderNumber, 'Regional Fulfillment Hub');
      if (this.metricsService) {
        this.metricsService.dispatchedTotal.inc();
      }
    }
    this.logger.log(`Successfully created shipment for order #${orderNumber} via Saga event`);
  }

  private getStatusString(raw: Record<string, any>): string {
    const val = raw.orderStatus || raw.status || raw.eventType;
    return typeof val === 'string' ? val.toUpperCase() : '';
  }

  private async handleOrderEvent(raw: Record<string, any>): Promise<void> {
    const orderNumber = raw.orderNumber || raw.order_number;
    if (!orderNumber || !this.shipmentRepo) return;

    const rawStatus = this.getStatusString(raw);

    if (rawStatus === 'CANCELLED' || rawStatus === 'ORDER_CANCELLED') {
      await this.handleOrderCancelled(orderNumber);
    } else if (rawStatus === 'SHIPPED' || rawStatus === 'ORDER_SHIPPED') {
      await this.handleOrderShipped(orderNumber);
    } else if (rawStatus === 'DELIVERED' || rawStatus === 'ORDER_DELIVERED') {
      await this.handleOrderDelivered(orderNumber);
    }
  }

  private async handleOrderCancelled(orderNumber: string): Promise<void> {
    const shipment = await this.shipmentRepo?.findOne({ where: { orderNumber } });
    if (!shipment || shipment.status === ShipmentStatus.CANCELLED || shipment.status === ShipmentStatus.DELIVERED) {
      return;
    }
    shipment.status = ShipmentStatus.CANCELLED;
    await this.shipmentRepo?.save(shipment);
    this.logger.log(`Shipment for order #${orderNumber} marked as CANCELLED via async Kafka event`);
    await this.metricsService?.refreshFromDatabase();
  }

  private async handleOrderShipped(orderNumber: string): Promise<void> {
    const shipment = await this.shipmentRepo?.findOne({ where: { orderNumber } });
    if (!shipment || shipment.status === ShipmentStatus.DISPATCHED || shipment.status === ShipmentStatus.DELIVERED) {
      return;
    }
    shipment.status = ShipmentStatus.DISPATCHED;
    shipment.dispatchedAt = shipment.dispatchedAt || new Date();
    await this.shipmentRepo?.save(shipment);
    this.logger.log(`Shipment for order #${orderNumber} marked as DISPATCHED via async Kafka event`);
    await this.metricsService?.refreshFromDatabase();
  }

  private async handleOrderDelivered(orderNumber: string): Promise<void> {
    const shipment = await this.shipmentRepo?.findOne({ where: { orderNumber } });
    if (!shipment || shipment.status === ShipmentStatus.DELIVERED) {
      return;
    }
    shipment.status = ShipmentStatus.DELIVERED;
    shipment.deliveredAt = shipment.deliveredAt || new Date();
    if (!shipment.dispatchedAt) {
      shipment.dispatchedAt = shipment.deliveredAt;
    }
    await this.shipmentRepo?.save(shipment);
    this.logger.log(`Shipment for order #${orderNumber} marked as DELIVERED via async Kafka event`);
    await this.metricsService?.refreshFromDatabase();
  }

  async onModuleDestroy() {
    this.isShuttingDown = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    await this.consumer.disconnect();
  }
}
