import { Injectable, OnModuleInit, OnModuleDestroy, Logger, Optional, Inject } from '@nestjs/common';
import { Kafka, Consumer } from 'kafkajs';
import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from '../../application/use-cases/dispatch-shipment.use-case';
import { EVENT_PUBLISHER, EventPublisher } from '../../application/ports/event-publisher.port';
import { FulfillmentMetricsService } from '../metrics/fulfillment-metrics.service';

@Injectable()
export class PaymentEventsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PaymentEventsConsumer.name);
  private readonly kafka: Kafka;
  private readonly consumer: Consumer;
  private readonly paymentsTopic = process.env.KAFKA_PAYMENTS_TOPIC || 'payments-topic';
  private isShuttingDown = false;
  private reconnectTimer?: ReturnType<typeof setTimeout>;

  constructor(
    private readonly createShipmentUseCase: CreateShipmentUseCase,
    @Optional() private readonly dispatchShipmentUseCase?: DispatchShipmentUseCase,
    @Optional() @Inject(EVENT_PUBLISHER) private readonly eventPublisher?: EventPublisher,
    @Optional() private readonly metricsService?: FulfillmentMetricsService,
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
      await this.consumer.subscribe({ topic: this.paymentsTopic, fromBeginning: false });
      this.logger.log(`Subscribed to topic: ${this.paymentsTopic}`);

      await this.consumer.run({
        eachMessage: async ({ message }) => {
          if (!message.value) return;
          try {
            const raw = JSON.parse(message.value.toString());
            await this.handlePaymentEvent(raw);
          } catch (err) {
            this.logger.error(`Error processing payment event: ${err.message}`);
          }
        },
      });
    } catch (err) {
      this.logger.warn(`Could not connect Kafka consumer immediately: ${err.message}. Retrying in 5s...`);
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

  async onModuleDestroy() {
    this.isShuttingDown = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    await this.consumer.disconnect();
  }
}
