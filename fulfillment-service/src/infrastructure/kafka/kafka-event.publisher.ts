import { Injectable, OnModuleInit, OnModuleDestroy, Logger, Optional } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Kafka, Producer, Partitioners } from 'kafkajs';
import { randomUUID } from 'node:crypto';
import type { EventPublisher } from '../../application/ports/event-publisher.port';
import { ShipmentDispatchedEvent } from '../../domain/events/shipment-dispatched.event';
import { ShipmentDeliveredEvent } from '../../domain/events/shipment-delivered.event';
import { OutboxEventOrmEntity } from '../persistence/entities/outbox-event.orm-entity';
import { extractErrorMessage } from '../utils/error.util';

@Injectable()
export class KafkaEventPublisher implements EventPublisher, OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(KafkaEventPublisher.name);
  private readonly kafka: Kafka;
  private readonly producer: Producer;
  private readonly topic = process.env.KAFKA_FULFILLMENT_TOPIC || 'fulfillment-topic';
  private reconnectNeeded = false;
  private isShuttingDown = false;
  private reconnectTimer?: ReturnType<typeof setTimeout>;
  private outboxWatchdogTimer?: ReturnType<typeof setInterval>;

  constructor(
    @Optional()
    @InjectRepository(OutboxEventOrmEntity)
    private readonly outboxRepo?: Repository<OutboxEventOrmEntity>,
  ) {
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
    this.startOutboxWatchdog();
  }

  private async connectProducer() {
    if (this.isShuttingDown) return;
    try {
      await this.producer.connect();
      this.reconnectNeeded = false;
      this.logger.log(`Connected to Kafka brokers at ${process.env.KAFKA_BOOTSTRAP_SERVERS || 'localhost:9092'}`);
    } catch (err: unknown) {
      this.reconnectNeeded = true;
      const message = extractErrorMessage(err);
      this.logger.warn(`Could not connect Kafka producer immediately: ${message}. Retrying in 5s...`);
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
    if (this.outboxWatchdogTimer) {
      clearInterval(this.outboxWatchdogTimer);
    }
    await this.producer.disconnect();
  }

  private async ensureConnected() {
    if (this.reconnectNeeded) {
      await this.producer.connect();
      this.reconnectNeeded = false;
    }
  }

  /**
   * Builds CloudEvents 1.0 envelope with root backward-compatibility attributes.
   */
  private buildCloudEvent(eventType: string, aggregateId: string, data: Record<string, any>) {
    const eventId = randomUUID();
    return {
      specversion: '1.0',
      id: eventId,
      source: '/fulfillment-service',
      type: `com.georgegxx.fulfillment.${eventType.toLowerCase().replaceAll('_', '-')}`,
      time: new Date().toISOString(),
      datacontenttype: 'application/json',
      data: {
        eventType,
        ...data,
      },
      // Root fields for flat schema consumer compatibility
      eventType,
      ...data,
    };
  }

  /**
   * Persists event in transactional Outbox and dispatches to Kafka broker.
   */
  private async dispatchViaOutbox(
    eventType: string,
    orderNumber: string,
    domainData: Record<string, any>,
  ): Promise<void> {
    const cloudEvent = this.buildCloudEvent(eventType, orderNumber, domainData);
    const serialized = JSON.stringify(cloudEvent);

    let outboxEntry: OutboxEventOrmEntity | undefined;
    if (this.outboxRepo) {
      try {
        outboxEntry = this.outboxRepo.create({
          aggregateType: 'Shipment',
          aggregateId: orderNumber,
          eventType,
          payload: serialized,
          status: 'PENDING',
          retryCount: 0,
        });
        outboxEntry = await this.outboxRepo.save(outboxEntry);
      } catch (dbErr: unknown) {
        this.logger.warn(`Could not write outbox event for order #${orderNumber}: ${extractErrorMessage(dbErr)}`);
      }
    }

    try {
      await this.ensureConnected();
      await this.producer.send({
        topic: this.topic,
        messages: [
          {
            key: orderNumber,
            value: serialized,
            headers: {
              eventType,
              ce_specversion: '1.0',
              ce_type: cloudEvent.type,
              ce_source: cloudEvent.source,
              ce_id: cloudEvent.id,
            },
          },
        ],
      });

      if (outboxEntry && this.outboxRepo) {
        outboxEntry.status = 'PUBLISHED';
        outboxEntry.processedAt = new Date();
        await this.outboxRepo.save(outboxEntry);
      }

      this.logger.log(`Published ${eventType} for order #${orderNumber} (Outbox ID: ${outboxEntry?.id || cloudEvent.id})`);
    } catch (err: unknown) {
      const message = extractErrorMessage(err);
      this.logger.error(`Failed to dispatch ${eventType} for order #${orderNumber} immediately: ${message}. Retained in outbox.`);
      if (outboxEntry && this.outboxRepo) {
        outboxEntry.retryCount += 1;
        await this.outboxRepo.save(outboxEntry);
      }
    }
  }

  private startOutboxWatchdog() {
    if (!this.outboxRepo) return;
    this.outboxWatchdogTimer = setInterval(async () => {
      await this.flushPendingOutbox();
    }, 5000);
    this.outboxWatchdogTimer.unref?.();
  }

  /**
   * Asynchronous sweep that drains pending outbox events when Kafka connectivity recovers.
   */
  async flushPendingOutbox(): Promise<void> {
    if (!this.outboxRepo || this.isShuttingDown) return;
    try {
      const pendingEvents = await this.outboxRepo.find({
        where: { status: 'PENDING' },
        take: 25,
        order: { createdAt: 'ASC' },
      });

      if (!pendingEvents.length) return;

      await this.ensureConnected();

      for (const event of pendingEvents) {
        try {
          await this.producer.send({
            topic: this.topic,
            messages: [
              {
                key: event.aggregateId,
                value: event.payload,
                headers: { eventType: event.eventType },
              },
            ],
          });
          event.status = 'PUBLISHED';
          event.processedAt = new Date();
          await this.outboxRepo.save(event);
        } catch (dispatchErr: unknown) {
          event.retryCount += 1;
          if (event.retryCount >= 5) {
            event.status = 'FAILED';
          }
          await this.outboxRepo.save(event);
          this.logger.warn(`Outbox retry ${event.retryCount} failed for event ${event.id}: ${extractErrorMessage(dispatchErr)}`);
          break;
        }
      }
    } catch (err: unknown) {
      this.logger.debug(`Outbox watchdog cycle skipped: ${extractErrorMessage(err)}`);
    }
  }

  async publishDispatched(event: ShipmentDispatchedEvent): Promise<void> {
    await this.dispatchViaOutbox('SHIPMENT_DISPATCHED', event.orderNumber, {
      ...event,
      dispatchedAt: new Date().toISOString(),
    });
  }

  async publishDelivered(event: ShipmentDeliveredEvent): Promise<void> {
    await this.dispatchViaOutbox('SHIPMENT_DELIVERED', event.orderNumber, {
      ...event,
      deliveredAt: new Date().toISOString(),
    });
  }

  async publishFailed(orderNumber: string, reason: string): Promise<void> {
    await this.dispatchViaOutbox('SHIPMENT_FAILED', orderNumber, {
      orderNumber,
      reason,
      failedAt: new Date().toISOString(),
    });
  }

  async publishDlq(sourceTopic: string, rawMessage: unknown, error: string): Promise<void> {
    const dlqTopic = `${sourceTopic}.dlq`;
    try {
      await this.ensureConnected();
      await this.producer.send({
        topic: dlqTopic,
        messages: [
          {
            value: JSON.stringify({
              sourceTopic,
              payload: rawMessage,
              error,
              deadLetteredAt: new Date().toISOString(),
            }),
            headers: { errorType: 'PROCESSING_FAILURE' },
          },
        ],
      });
      this.logger.warn(`Routed unprocessable Kafka message from ${sourceTopic} to DLQ ${dlqTopic}: ${error}`);
    } catch (err: unknown) {
      const message = extractErrorMessage(err);
      this.logger.error(`Failed to route message to DLQ ${dlqTopic}: ${message}`);
    }
  }
}
