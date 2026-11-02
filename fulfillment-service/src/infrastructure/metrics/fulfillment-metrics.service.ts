import { Injectable } from '@nestjs/common';
import * as client from 'prom-client';

@Injectable()
export class FulfillmentMetricsService {
  private readonly registry: client.Registry;
  public readonly shipmentsTotal: client.Counter<string>;
  public readonly dispatchedTotal: client.Counter<string>;
  public readonly deliveredTotal: client.Counter<string>;
  public readonly httpRequests: client.Histogram<string>;

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

    this.httpRequests = new client.Histogram({
      name: 'http_server_requests_seconds',
      help: 'HTTP server request execution duration in seconds',
      labelNames: ['service', 'status', 'uri', 'method'],
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
      registers: [this.registry],
    });
  }

  async getMetrics(): Promise<string> {
    return await this.registry.metrics();
  }
}
