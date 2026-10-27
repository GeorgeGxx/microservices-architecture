import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { Kafka, Producer } from 'kafkajs';
import { EventPublisher } from '../../application/ports/event-publisher.port';
import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentDeliveredEvent } from '../../domain/events/shipment-delivered.event';

@Injectable()
export class KafkaEventPublisher implements EventPublisher, OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KafkaEventPublisher.name);
  private kafka: Kafka;
  private producer: Producer;
  private readonly topic = process.env.KAFKA_FULFILLMENT_TOPIC || 'fulfillment-topic';

  constructor() {
    const brokers = (process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092').split(',');
    this.kafka = new Kafka({
      clientId: 'fulfillment-service-publisher',
      brokers,
    });
    this.producer = this.kafka.producer();
  }

  async onModuleInit() {
    try {
      await this.producer.connect();
      this.logger.log(`Connected to Kafka brokers at ${process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092'}`);
    } catch (err) {
      this.logger.warn(`Could not connect Kafka producer immediately: ${err.message}`);
    }
  }

  async onModuleDestroy() {
    await this.producer.disconnect();
  }

  async publishDispatched(event: ShipmentDispatchedEvent): Promise<void> {
    try {
      await this.producer.send({
        topic: this.topic,
        messages: [
          {
            key: event.orderNumber,
            value: JSON.stringify({
              eventType: 'SHIPMENT_DISPATCHED',
              ...event,
            }),
            headers: { eventType: 'SHIPMENT_DISPATCHED' },
          },
        ],
      });
      this.logger.log(`Published ShipmentDispatchedEvent for order #${event.orderNumber} (Tracking: ${event.trackingNumber})`);
    } catch (err) {
      this.logger.error(`Failed to publish ShipmentDispatchedEvent for order #${event.orderNumber}: ${err.message}`);
    }
  }

  async publishDelivered(event: ShipmentDeliveredEvent): Promise<void> {
    try {
      await this.producer.send({
        topic: this.topic,
        messages: [
          {
            key: event.orderNumber,
            value: JSON.stringify({
              eventType: 'SHIPMENT_DELIVERED',
              ...event,
            }),
            headers: { eventType: 'SHIPMENT_DELIVERED' },
          },
        ],
      });
      this.logger.log(`Published ShipmentDeliveredEvent for order #${event.orderNumber}`);
    } catch (err) {
      this.logger.error(`Failed to publish ShipmentDeliveredEvent for order #${event.orderNumber}: ${err.message}`);
    }
  }
}
