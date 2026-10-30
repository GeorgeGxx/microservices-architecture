import { Injectable, OnModuleInit, OnModuleDestroy, Logger } from '@nestjs/common';
import { Kafka, Producer, Partitioners } from 'kafkajs';
import { EventPublisher } from '../../application/ports/event-publisher.port';
import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentDeliveredEvent } from '../../domain/events/shipment-delivered.event';

@Injectable()
export class KafkaEventPublisher implements EventPublisher, OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KafkaEventPublisher.name);
  private readonly kafka: Kafka;
  private readonly producer: Producer;
  private readonly topic = process.env.KAFKA_FULFILLMENT_TOPIC || 'fulfillment-topic';
  private reconnectNeeded = false;
  private isShuttingDown = false;
  private reconnectTimer?: ReturnType<typeof setTimeout>;

  constructor() {
    const brokers = (process.env.KAFKA_BOOTSTRAP_SERVERS || process.env.KAFKA_BROKERS || 'localhost:9092').split(',');
    this.kafka = new Kafka({
      clientId: 'fulfillment-service-publisher',
      brokers,
      retry: {
        initialRetryTime: 500,
        retries: 15,
      },
    });
    this.producer = this.kafka.producer({
      createPartitioner: Partitioners.DefaultPartitioner,
    });
  }

  async onModuleInit() {
    await this.connectProducer();
  }

  private async connectProducer() {
    if (this.isShuttingDown) return;
    try {
      await this.producer.connect();
      this.reconnectNeeded = false;
      this.logger.log(`Connected to Kafka brokers at ${process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092'}`);
    } catch (err) {
      this.reconnectNeeded = true;
      this.logger.warn(`Could not connect Kafka producer immediately: ${err.message}. Retrying in 5s...`);
      if (!this.isShuttingDown) {
        this.reconnectTimer = setTimeout(() => {
          void this.connectProducer();
        }, 5000);
        this.reconnectTimer.unref?.();
      }
    }
  }

  async onModuleDestroy() {
    this.isShuttingDown = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }
    await this.producer.disconnect();
  }

  private async ensureConnected() {
    if (this.reconnectNeeded) {
      await this.producer.connect();
      this.reconnectNeeded = false;
    }
  }

  async publishDispatched(event: ShipmentDispatchedEvent): Promise<void> {
    try {
      await this.ensureConnected();
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
      await this.ensureConnected();
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

  async publishFailed(orderNumber: string, reason: string): Promise<void> {
    try {
      await this.ensureConnected();
      await this.producer.send({
        topic: this.topic,
        messages: [
          {
            key: orderNumber,
            value: JSON.stringify({
              eventType: 'SHIPMENT_FAILED',
              orderNumber,
              reason,
              failedAt: new Date().toISOString(),
            }),
            headers: { eventType: 'SHIPMENT_FAILED' },
          },
        ],
      });
      this.logger.warn(`Published ShipmentFailedEvent for order #${orderNumber} (reason: ${reason})`);
    } catch (err) {
      this.logger.error(`Failed to publish ShipmentFailedEvent for order #${orderNumber}: ${err.message}`);
    }
  }
}
