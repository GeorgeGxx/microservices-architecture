import { Component, ChangeDetectionStrategy, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SystemStatusService, ServiceHealth } from '../../../core/services/system-status.service';

export interface TopologyNode {
  id: string;
  name: string;
  role: string;
  category: 'gateway' | 'service' | 'data' | 'eda' | 'iam';
  port: string;
  namespace: string;
  tech: string;
  description: string;
  x: number; // Percentage or coordinate for layout
  y: number;
}

@Component({
  selector: 'app-architecture-topology',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './architecture-topology.component.html',
  styleUrl: './architecture-topology.component.css'
})
export class ArchitectureTopologyComponent {
  readonly statusService = inject(SystemStatusService);

  readonly selectedNodeId = signal<string>('api-gateway');

  readonly nodes: TopologyNode[] = [
    {
      id: 'api-gateway',
      name: 'API Gateway',
      role: 'Cloud Edge & Rate Limiter',
      category: 'gateway',
      port: '8080',
      namespace: 'dev',
      tech: 'Spring Cloud Gateway / Istio Ingress',
      description: 'Unified edge reverse proxy, JWT bearer verification, resilience circuit breakers and dynamic routing.',
      x: 15,
      y: 50
    },
    {
      id: 'keycloak',
      name: 'Keycloak IAM',
      role: 'OAuth2 / OpenID Connect',
      category: 'iam',
      port: '8181',
      namespace: 'auth',
      tech: 'Keycloak 26 Quarkus',
      description: 'Enterprise identity provider managing SSO, RBAC roles (ADMIN, USER) and token signing.',
      x: 15,
      y: 18
    },
    {
      id: 'products-service',
      name: 'Products Service',
      role: 'Catalog & Dynamic Pricing',
      category: 'service',
      port: '8081',
      namespace: 'dev',
      tech: 'Spring Boot 4.0.8 / Java 25',
      description: 'Manages catalog inventory items, multi-currency conversion, and search filtering.',
      x: 48,
      y: 20
    },
    {
      id: 'orders-service',
      name: 'Orders Service',
      role: 'Saga Checkout Coordinator',
      category: 'service',
      port: '8082',
      namespace: 'dev',
      tech: 'Spring Boot 4.0.8 / JPA',
      description: 'Orchestrates distributed cart checkouts and publishes OrderCreatedEvent to Kafka broker.',
      x: 48,
      y: 45
    },
    {
      id: 'inventory-service',
      name: 'Inventory Service',
      role: 'Stock Reservation Engine',
      category: 'service',
      port: '8083',
      namespace: 'dev',
      tech: 'Spring Boot 4.0.8 / Locking',
      description: 'Handles pessimistic concurrency locking to avoid overselling, consumes Kafka orders events.',
      x: 48,
      y: 70
    },
    {
      id: 'notification-service',
      name: 'Notification Service',
      role: 'Customer Alerts & Mailer',
      category: 'service',
      port: '8084',
      namespace: 'dev',
      tech: 'Spring Boot 4.0.8 / Kafka Consumer',
      description: 'Asynchronously consumes Kafka notifications and issues customer transactional emails.',
      x: 48,
      y: 92
    },
    {
      id: 'kafka',
      name: 'Apache Kafka',
      role: 'Event Streaming Backbone',
      category: 'eda',
      port: '9092',
      namespace: 'data',
      tech: 'Confluent CP-Kafka 7.8 (KRaft)',
      description: 'Ultra-low latency event streaming broker connecting Orders, Inventory and Notification sagas.',
      x: 82,
      y: 50
    },
    {
      id: 'redis',
      name: 'Redis L2 Cache',
      role: 'Sub-millisecond Session Cache',
      category: 'data',
      port: '6379',
      namespace: 'data',
      tech: 'Redis 7.4 Alpine',
      description: 'In-memory caching for products catalog, rate-limiting counters, and session states.',
      x: 82,
      y: 20
    },
    {
      id: 'postgres',
      name: 'PostgreSQL Relational DBs',
      role: 'Multi-Tenant ACID Persistence',
      category: 'data',
      port: '5432',
      namespace: 'data',
      tech: 'PostgreSQL 17.2',
      description: 'Isolated schemas per bounded context (ms_products, ms_orders, ms_inventory).',
      x: 82,
      y: 80
    }
  ];

  readonly activeNode = computed(() => {
    const id = this.selectedNodeId();
    return this.nodes.find(n => n.id === id) || this.nodes[0];
  });

  selectNode(id: string): void {
    this.selectedNodeId.set(id);
  }

  getNodeStatus(id: string): ServiceHealth['status'] {
    const s = this.statusService.services().find(srv => srv.id === id);
    return s ? s.status : 'UP';
  }

  getNodeLatency(id: string): number | undefined {
    const s = this.statusService.services().find(srv => srv.id === id);
    return s?.latencyMs;
  }
}
