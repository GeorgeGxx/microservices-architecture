# 📄 ADR-003: Asynchronous Event-Driven Choreography with Apache Kafka (KRaft)

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Solution Architect, Tech Lead, SRE Lead
* **Date:** 2026-01-25
* **Technical Story:** Asynchronous Decoupling & Saga Compensation

---

## 🎯 Context & Problem Statement

Synchronous HTTP REST calls between `orders-service`, `inventory-service`, and `notification-service` during checkout create temporal coupling, amplify latency, and introduce catastrophic cascading failures if a downstream service experiences high load or downtime.

We need an enterprise event-streaming backbone that provides:
1. Guaranteed at-least-once message delivery.
2. High throughput with persistent ordered event partitioning.
3. Event-driven Saga choreography (e.g. order placement $\rightarrow$ stock reserve $\rightarrow$ customer notification $\rightarrow$ stock compensation on cancel).
4. Native integration with Kubernetes event-driven autoscaling (KEDA).

---

## ⚖️ Decision Drivers

1. **Decoupled Asynchrony:** Placing an order must succeed immediately without blocking on email delivery or SMS alerts.
2. **Operational Simplicity:** Avoid legacy ZooKeeper cluster management overhead.
3. **Partition Ordering & Consumer Groups:** Partition by order ID or customer ID to guarantee in-order state transitions.
4. **Resilience & Backpressure:** Enable consumer services to process spikes at their own pace without exhausting system resources.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Synchronous REST API Calls with Circuit Breakers (Resilience4j)
* **Option 2:** Apache Kafka with KRaft Consensus (ZooKeeper-less)
* **Option 3:** RabbitMQ (AMQP Message Broker)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Synchronous REST | Option 2: Apache Kafka (KRaft) | Option 3: RabbitMQ |
| :--- | :---: | :---: | :---: | :---: |
| **Decoupling & Temporal Independence** | 5 | 0 (Baseline) | **+1** (Full asynchronous decoupling) | +1 (Asynchronous) |
| **Throughput & Event Replayability** | 5 | 0 (Baseline) | **+1** (Distributed append log + replay) | 0 (Queue drain model) |
| **KEDA Event-Driven Autoscaling** | 4 | 0 (Baseline) | **+1** (Native lag scaler) | 0 (Queue length scaler) |
| **Operational Simplicity (No ZooKeeper)** | 4 | 0 (Baseline: HTTP) | **0** (KRaft eliminates ZooKeeper) | +1 (Lightweight Erlang) |
| **Saga Compensation Support** | 4 | 0 (Baseline) | **+1** (Auditable immutable events) | 0 (Basic ack/nack) |
| **Weighted Total** | - | **0.00** | **+18 (WINNER)** | +9.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (Apache Kafka in KRaft mode)**.

### Positive Consequences
* **Decoupled Notification Pipeline:** `notification-service` consumes `OrderPlacedEvent` from topic `orders-topic` and dispatches real-time SSE streams without adding latency to checkout.
* **Saga Compensation:** When an order is cancelled (`OrderCancelledEvent`), compensating transactions automatically restore stock in `inventory-service`.
* **Zero ZooKeeper Overhead:** KRaft consensus runs natively inside Kafka brokers, halving memory usage on local Minikube.
* **Autoscaling via KEDA:** `notification-service-scaler` automatically spins up additional pods when Kafka consumer lag exceeds 10 messages.

### Negative Consequences / Trade-offs
* Requires careful handling of idempotent consumers (addressed via Redis `SETNX` with 7-day TTL).
