import { Injectable, OnModuleInit, Logger, Optional } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as client from 'prom-client';
import { ShipmentOrmEntity } from '../persistence/entities/shipment.orm-entity';
import { ShipmentStatus } from '../../domain/value-objects/shipment-status.enum';
import { extractErrorMessage } from '../utils/error.util';

@Injectable()
export class FulfillmentMetricsService implements OnModuleInit {
  private readonly logger = new Logger(FulfillmentMetricsService.name);
  private readonly registry: client.Registry;
  public readonly shipmentsTotal: client.Gauge<string>;
  public readonly dispatchedTotal: client.Gauge<string>;
  public readonly deliveredTotal: client.Gauge<string>;
  public readonly httpRequests: client.Histogram<string>;
  private isRefreshing = false;

  constructor(
    @Optional()
    @InjectRepository(ShipmentOrmEntity)
    private readonly shipmentRepo?: Repository<ShipmentOrmEntity>,
  ) {
    this.registry = new client.Registry();
    client.collectDefaultMetrics({ register: this.registry });

    this.shipmentsTotal = new client.Gauge({
      name: 'ecommerce_shipments_total',
      help: 'Total number of shipments by status and carrier in fulfillment-service',
      labelNames: ['status', 'carrier'],
      registers: [this.registry],
    });

    this.dispatchedTotal = new client.Gauge({
      name: 'ecommerce_shipments_dispatched_total',
      help: 'Total number of shipments dispatched from warehouse',
      registers: [this.registry],
    });

    this.deliveredTotal = new client.Gauge({
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
    this.dispatchedTotal.set(0);
    this.deliveredTotal.set(0);
    for (const carrier of ['DHL Express', 'FedEx']) {
      this.shipmentsTotal.set({ status: ShipmentStatus.AWAITING_PICKUP, carrier }, 0);
    }
  }

  async onModuleInit(): Promise<void> {
    await this.refreshFromDatabase();
  }

  public async refreshFromDatabase(): Promise<void> {
    if (!this.shipmentRepo || this.isRefreshing) return;
    this.isRefreshing = true;
    try {
      this.shipmentsTotal.reset();
      for (const carrier of ['DHL Express', 'FedEx']) {
        for (const status of [
          ShipmentStatus.AWAITING_PICKUP,
          ShipmentStatus.DISPATCHED,
          ShipmentStatus.DELIVERED,
          ShipmentStatus.CANCELLED,
        ]) {
          this.shipmentsTotal.set({ status, carrier }, 0);
        }
      }

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
          this.shipmentsTotal.set({ status: row.status || ShipmentStatus.AWAITING_PICKUP, carrier: row.carrier }, count);
        }
      }

      const dispatchedCount = await this.shipmentRepo
        .createQueryBuilder('s')
        .where('s.dispatched_at IS NOT NULL')
        .getCount();

      if (typeof dispatchedCount === 'number' && !Number.isNaN(dispatchedCount)) {
        this.dispatchedTotal.set(dispatchedCount);
      }

      const deliveredCount = await this.shipmentRepo
        .createQueryBuilder('s')
        .where('s.delivered_at IS NOT NULL')
        .getCount();

      if (typeof deliveredCount === 'number' && !Number.isNaN(deliveredCount)) {
        this.deliveredTotal.set(deliveredCount);
      }

      this.logger.log(
        `Fulfillment metrics synced from database: ${shipmentsGrouped.length} carrier/status groups, ${dispatchedCount} dispatched, ${deliveredCount} delivered.`,
      );
    } catch (err: unknown) {
      const message = extractErrorMessage(err);
      this.logger.warn(`Could not sync fulfillment metrics from database: ${message}`);
    } finally {
      this.isRefreshing = false;
    }
  }

  async getMetrics(): Promise<string> {
    await this.refreshFromDatabase();
    return await this.registry.metrics();
  }
}
