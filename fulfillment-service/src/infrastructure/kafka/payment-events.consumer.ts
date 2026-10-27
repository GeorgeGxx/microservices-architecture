import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { Kafka, Consumer } from 'kafkajs';
import { CreateShipmentUseCase } from '../../application/use-cases/create-shipment.use-case';

@Injectable()
export class PaymentEventsConsumer implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(PaymentEventsConsumer.name);
  private kafka: Kafka;
  private consumer: Consumer;
  private readonly paymentsTopic = process.env.KAFKA_PAYMENTS_TOPIC || 'payments-topic';

  constructor(private readonly createShipmentUseCase: CreateShipmentUseCase) {
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

            // Trigger Saga fulfillment upon successful payment
            this.logger.log(`Received PaymentCompleted for order #${orderNumber}, creating shipment...`);
            await this.createShipmentUseCase.execute({
              orderNumber,
              recipientName: raw.customer_name || 'Customer',
              street: raw.shipping_address || '100 Main St',
              city: raw.city || 'Metropolis',
              postalCode: raw.postal_code || '10001',
              phone: raw.phone,
              carrier: 'DHL Express',
            });
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
