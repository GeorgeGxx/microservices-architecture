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
import {
  parseCloudEvent,
  PaymentEventContract,
  OrderEventContract,
} from '../../domain/events/contracts/cloud-event.contract';
import { IdempotencyService } from '../outbox/idempotency.service';
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
    @Optional()
    private readonly idempotencyService?: IdempotencyService,
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
            const parsed = parseCloudEvent(raw);

            // Exactly-once semantic idempotency check
            const messageId =
              parsed.id ||
              message.key?.toString() ||
              `${topic}:${(parsed.data as any).orderNumber || (parsed.data as any).order_number || 'none'}:${message.offset}`;

            if (this.idempotencyService && (await this.idempotencyService.isProcessed(messageId))) {
              this.logger.debug(`Skipping already processed message #${messageId} on topic ${topic}`);
              return;
            }

            if (topic === this.ordersTopic) {
              await this.handleOrderEvent(parsed.data as OrderEventContract);
            } else {
              await this.handlePaymentEvent(parsed.data as PaymentEventContract);
            }

            if (this.idempotencyService) {
              await this.idempotencyService.markProcessed(messageId, 'fulfillment-consumer', parsed.eventType);
            }
          } catch (err: unknown) {
            const errorMsg = extractErrorMessage(err);
            this.logger.error(`Error processing Kafka event on topic ${topic}: ${errorMsg}`);
            if (this.eventPublisher?.publishDlq) {
              await this.eventPublisher.publishDlq(topic, message.value.toString(), errorMsg);
            }
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

  private isNegativePaymentEvent(payment: PaymentEventContract): boolean {
    const eventType = String(payment.event_type || '').toUpperCase();
    const status = String(payment.status || '').toUpperCase();
    return (
      eventType === 'PAYMENT_FAILED' ||
      eventType === 'PAYMENT_REFUNDED' ||
      status === 'FAILED' ||
      status === 'REFUNDED' ||
      Boolean(payment.error_code)
    );
  }

  private resolveCarrier(rawMethod?: unknown): string {
    if (typeof rawMethod === 'string') {
      const normalized = rawMethod.trim();
      if (/fedex/i.test(normalized)) {
        return 'FedEx';
      }
      if (/dhl/i.test(normalized) || /express|priority|standard/i.test(normalized)) {
        return 'DHL Express';
      }
      return normalized || 'DHL Express';
    }
    return 'DHL Express';
  }

  private async handlePaymentEvent(payment: PaymentEventContract): Promise<void> {
    const orderNumber = payment.order_number || (payment as any).orderNumber;
    if (!orderNumber || this.isNegativePaymentEvent(payment)) {
      return;
    }

    const street = payment.shipping_address || (payment as any).street || '100 Main St';
    if (street.includes('FAIL_SHIPMENT')) {
      const reason = 'Undeliverable shipping address rejected by carrier validation';
      this.logger.warn(`Fulfillment validation failed for order #${orderNumber}: ${reason}`);
      if (this.eventPublisher?.publishFailed) {
        await this.eventPublisher.publishFailed(orderNumber, reason);
      }
      return;
    }

    const carrier = this.resolveCarrier(payment.delivery_method || (payment as any).carrier);

    this.logger.log(`Received PaymentCompleted for order #${orderNumber}, creating shipment via ${carrier}...`);
    const created = await this.createShipmentUseCase.execute({
      orderNumber,
      recipientName: payment.customer_name || (payment as any).recipientName || 'Customer',
      street,
      city: payment.city || 'Metropolis',
      postalCode: payment.postal_code || (payment as any).postalCode || '10001',
      phone: payment.phone,
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

  private async handleOrderEvent(order: OrderEventContract): Promise<void> {
    const orderNumber = order.orderNumber || (order as any).order_number;
    if (!orderNumber || !this.shipmentRepo) return;

    const rawStatus = String(order.orderStatus || (order as any).status || '').toUpperCase();

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
    if (this.metricsService?.refreshFromDatabase) {
      await this.metricsService.refreshFromDatabase();
    }
    this.logger.warn(`Shipment for cancelled order #${orderNumber} was marked CANCELLED`);
  }

  private async handleOrderShipped(orderNumber: string): Promise<void> {
    const shipment = await this.shipmentRepo?.findOne({ where: { orderNumber } });
    if (!shipment || shipment.status === ShipmentStatus.DELIVERED) return;
    if (shipment.status !== ShipmentStatus.DISPATCHED) {
      shipment.status = ShipmentStatus.DISPATCHED;
      shipment.dispatchedAt = new Date();
      await this.shipmentRepo?.save(shipment);
      if (this.metricsService?.refreshFromDatabase) {
        await this.metricsService.refreshFromDatabase();
      }
      this.logger.log(`Shipment for order #${orderNumber} marked DISPATCHED via upstream event`);
    }
  }

  private async handleOrderDelivered(orderNumber: string): Promise<void> {
    const shipment = await this.shipmentRepo?.findOne({ where: { orderNumber } });
    if (!shipment) return;
    if (shipment.status !== ShipmentStatus.DELIVERED) {
      shipment.status = ShipmentStatus.DELIVERED;
      shipment.deliveredAt = new Date();
      await this.shipmentRepo?.save(shipment);
      if (this.metricsService?.refreshFromDatabase) {
        await this.metricsService.refreshFromDatabase();
      }
      this.logger.log(`Shipment for order #${orderNumber} marked DELIVERED via upstream event`);
    }
  }

  async onModuleDestroy() {
    this.isShuttingDown = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    await this.consumer.disconnect();
  }
}
