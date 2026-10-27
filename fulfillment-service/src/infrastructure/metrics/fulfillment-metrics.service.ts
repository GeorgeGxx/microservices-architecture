import { Injectable } from '@nestjs/common';
import * as client from 'prom-client';

@Injectable()
export class FulfillmentMetricsService {
  private readonly registry: client.Registry;
  public readonly shipmentsTotal: client.Counter<string>;
  public readonly dispatchedTotal: client.Counter<string>;
  public readonly deliveredTotal: client.Counter<string>;

  constructor() {
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
  }

  async getMetrics(): Promise<string> {
    return this.registry.metrics();
  }
}
