import { Injectable, OnModuleInit, Logger, Optional } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as client from 'prom-client';
import { ShipmentOrmEntity } from '../persistence/entities/shipment.orm-entity';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';

@Injectable()
export class FulfillmentMetricsService implements OnModuleInit {
  private readonly logger = new Logger(FulfillmentMetricsService.name);
  private readonly registry: client.Registry;
  public readonly shipmentsTotal: client.Counter<string>;
  public readonly dispatchedTotal: client.Counter<string>;
  public readonly deliveredTotal: client.Counter<string>;
  public readonly httpRequests: client.Histogram<string>;

  constructor(
    @Optional()
    @InjectRepository(ShipmentOrmEntity)
    private readonly shipmentRepo?: Repository<ShipmentOrmEntity>,
  ) {
    this.registry = new client.Registry();
    client.collectDefaultMetrics({ register: this.registry });

    this.shipmentsTotal = new client.Counter({
      name: 'ecommerce_shipments_total',
      help: 'Total number of shipments created in fulfillment-service',
      labelNames: ['status', 'carrier'],
      registers: [this.registry],
    });

    this.dispatchedTotal = new client.Counter({
      name: 'ecommerce_shipments_dispatched_total',
      help: 'Total number of shipments dispatched from warehouse',
      registers: [this.registry],
    });

    this.deliveredTotal = new client.Counter({
      name: 'ecommerce_shipments_delivered_total',
      help: 'Total number of shipments successfully delivered to customers',
      registers: [this.registry],
    });

    this.httpRequests = new client.Histogram({
      name: 'http_server_requests_seconds',
      help: 'HTTP server request execution duration in seconds',
      labelNames: ['service', 'status', 'uri', 'method'],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
      registers: [this.registry],
    });

    // Ensure zero-values exist immediately so Prometheus scrapes always find active series
    this.dispatchedTotal.inc(0);
    this.deliveredTotal.inc(0);
    for (const carrier of ['DHL Express', 'FedEx']) {
      this.shipmentsTotal.inc({ status: ShipmentStatus.AWAITING_PICKUP, carrier }, 0);
    }
  }

  async onModuleInit(): Promise<void> {
    if (!this.shipmentRepo) return;
    try {
      const shipmentsGrouped = await this.shipmentRepo
        .createQueryBuilder('s')
        .select('s.carrier', 'carrier')
        .addSelect('s.status', 'status')
        .addSelect('COUNT(*)', 'count')
        .groupBy('s.carrier')
        .addGroupBy('s.status')
        .getRawMany<{ carrier: string; status: string; count: string }>();

      for (const row of shipmentsGrouped) {
        const count = Number.parseInt(row.count, 10);
        if (count > 0 && row.carrier) {
          this.shipmentsTotal.inc({ status: row.status || ShipmentStatus.AWAITING_PICKUP, carrier: row.carrier }, count);
        }
      }

      const dispatchedCount = await this.shipmentRepo
        .createQueryBuilder('s')
        .where('s.dispatched_at IS NOT NULL')
        .getCount();

      if (dispatchedCount > 0) {
        this.dispatchedTotal.inc(dispatchedCount);
      }

      const deliveredCount = await this.shipmentRepo
        .createQueryBuilder('s')
        .where('s.delivered_at IS NOT NULL')
        .getCount();

      if (deliveredCount > 0) {
        this.deliveredTotal.inc(deliveredCount);
      }

      this.logger.log(
        `Fulfillment metrics seeded from PostgreSQL: ${shipmentsGrouped.length} carrier/status groups, ${dispatchedCount} dispatched, ${deliveredCount} delivered.`,
      );
    } catch (err) {
      this.logger.warn(`Could not seed fulfillment metrics from database: ${err.message}`);
    }
  }

  async getMetrics(): Promise<string> {
    return await this.registry.metrics();
  }
}
