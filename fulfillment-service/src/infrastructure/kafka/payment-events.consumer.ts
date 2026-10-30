import { Injectable, OnModuleInit, OnModuleDestroy, Logger, Optional, Inject } from '@nestjs/common';
import { Kafka, Consumer } from 'kafkajs';
import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';
import { DispatchShipmentUseCase } from '../../application/use-cases/dispatch-shipment.use-case';
import { EVENT_PUBLISHER, EventPublisher } from '../../application/ports/event-publisher.port';

@Injectable()
export class PaymentEventsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PaymentEventsConsumer.name);
  private readonly kafka: Kafka;
  private readonly consumer: Consumer;
  private readonly paymentsTopic = process.env.KAFKA_PAYMENTS_TOPIC || 'payments-topic';

  constructor(
    private readonly createShipmentUseCase: CreateShipmentUseCase,
    @Optional() private readonly dispatchShipmentUseCase?: DispatchShipmentUseCase,
    @Optional() @Inject(EVENT_PUBLISHER) private readonly eventPublisher?: EventPublisher,
  ) {
    const brokers = (process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092').split(',');
    this.kafka = new Kafka({
      clientId: 'fulfillment-service-consumer',
      brokers,
    });
    this.consumer = this.kafka.consumer({
      groupId: process.env.KAFKA_GROUP_ID || 'fulfillment-service-group',
    });
  }

  async onModuleInit() {
    try {
      await this.consumer.connect();
      await this.consumer.subscribe({ topic: this.paymentsTopic, fromBeginning: false });
      this.logger.log(`Subscribed to topic: ${this.paymentsTopic}`);

      await this.consumer.run({
        eachMessage: async ({ message }) => {
          if (!message.value) return;
          try {
            const raw = JSON.parse(message.value.toString());
            const orderNumber = raw.order_number || raw.orderNumber;
            if (!orderNumber) return;

            // Ignore negative payment events (PAYMENT_FAILED / PAYMENT_REFUNDED)
            const eventType = raw.event_type || raw.eventType;
            const status = raw.status || raw.paymentStatus;
            if (
              eventType === 'PAYMENT_FAILED' ||
              eventType === 'PAYMENT_REFUNDED' ||
              status === 'FAILED' ||
              status === 'REFUNDED' ||
              raw.error_code
            ) {
              return;
            }

            const street = raw.shipping_address || raw.street || '100 Main St';
            if (String(street).includes('FAIL_SHIPMENT')) {
              const reason = 'Undeliverable shipping address rejected by carrier validation';
              this.logger.warn(`Fulfillment validation failed for order #${orderNumber}: ${reason}`);
              if (this.eventPublisher?.publishFailed) {
                await this.eventPublisher.publishFailed(orderNumber, reason);
              }
              return;
            }

            // Trigger Saga fulfillment upon successful payment
            this.logger.log(`Received PaymentCompleted for order #${orderNumber}, creating shipment...`);
            await this.createShipmentUseCase.execute({
              orderNumber,
              recipientName: raw.customer_name || raw.recipientName || 'Customer',
              street,
              city: raw.city || 'Metropolis',
              postalCode: raw.postal_code || raw.postalCode || '10001',
              phone: raw.phone,
              carrier: 'DHL Express',
            });

            if (this.dispatchShipmentUseCase) {
              await this.dispatchShipmentUseCase.execute(orderNumber, 'Regional Fulfillment Hub');
            }
            this.logger.log(`Successfully created shipment for order #${orderNumber} via Saga event`);
          } catch (err) {
            this.logger.error(`Error processing payment event: ${err.message}`);
          }
        },
      });
    } catch (err) {
      this.logger.warn(`Could not connect Kafka consumer immediately: ${err.message}`);
    }
  }

  async onModuleDestroy() {
    await this.consumer.disconnect();
  }
}
