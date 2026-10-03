# 📄 ADR-010: Cross-Region Warm Standby & Business Continuity Strategy (BCDR)

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Platform/DevOps Lead, SecOps Lead, Cloud Architect
* **Date:** 2026-10-02
* **Technical Story:** Cross-Region Disaster Recovery (DR) & RTO/RPO Governance

---

## 🎯 Context & Problem Statement

While the platform features high availability within an individual region (Multi-AZ deployments, Kubernetes replica sets, and KEDA horizontal autoscaling), a regional cloud outage, catastrophic network partition, ransomware infection, or physical datacenter disaster would render the system unavailable, leading to substantial financial loss, customer trust degradation, and regulatory compliance failure.

We need a standardized **Business Continuity and Disaster Recovery (BCDR)** strategy that:
1. Meets Tier-1 business requirements: Recovery Time Objective (**RTO < 15 minutes**) and Recovery Point Objective (**RPO < 1 minute**).
2. Protects mission-critical stateful storage (PostgreSQL databases per service and Kafka event streams).
3. Provides automated edge traffic failover (DNS/Anycast) without human intervention bottlenecks.
4. Balances business continuity guarantees against cloud operational expenditure.

---

## ⚖️ Decision Drivers

1. **RTO & RPO Stringency:** Minimizing revenue loss and preventing data loss for committed orders.
2. **Cost Efficiency:** Avoiding excessive idle cloud spend in secondary regions during normal operations.
3. **Operational Simplicity & Automation:** Deterministic runbooks with automated edge health checks and KEDA scaling.
4. **Data Integrity & Immutability:** Protecting backups against ransomware encryption via WORM Object Lock.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Backup & Restore (Cold DR - Scheduled nightly backups restored on-demand)
* **Option 2:** Pilot Light (Minimal core infrastructure active; state continuously replicated; compute spun up on disaster)
* **Option 3:** Warm Standby (Secondary region running at 25% compute capacity; continuous DB replication; auto-scaling to 100% on failover)
* **Option 4:** Multi-Region Active-Active (Fully redundant clusters in dual regions processing traffic concurrently)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Backup & Restore | Option 2: Pilot Light | Option 3: Warm Standby (Selected) | Option 4: Active-Active |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **RTO Compliance (< 15 min)** | 5 | 0 (Baseline: 4-8 hrs) | +1 (30-60 min) | **+1 (< 15 min)** | +1 (0-30 sec) |
| **RPO Compliance (< 1 min)** | 5 | 0 (Baseline: 1-24 hrs) | +1 (< 5 min) | **+1 (< 1 min via streaming replica)** | +1 (0 sec) |
| **Cloud Cost Optimization** | 4 | 0 (Baseline: cheapest) | 0 (Moderate spend) | **-1 (25% compute overhead)** | -1 (100% duplicate spend) |
| **Operational Simplicity** | 4 | 0 (Baseline) | 0 (Complex cold-start) | **+1 (Pre-warmed cluster + KEDA)** | -1 (Complex distributed locks/conflicts) |
| **Ransomware / WORM Protection** | 4 | 0 (Baseline) | +1 (Object Lock) | **+1 (Immutable S3 WAL archive)** | 0 (Instant replication risks malware spread) |
| **Weighted Total** | - | **0.00** | **+14.00** | **+18.00 (WINNER)** | +6.00 |

*Scoring: +1 = Superior to baseline, 0 = Equal to baseline, -1 = Inferior to baseline.*

---

## 💡 Decision Outcome

Chosen option: **Option 3 (Cross-Region Warm Standby)**.

### Architectural Blueprint:
* **Primary Region (`us-east-1`):** Serves 100% of production traffic across Multi-AZ EKS, RDS PostgreSQL, and Kafka KRaft.
* **Secondary Region (`us-west-2`):** Runs a pre-warmed EKS cluster at 25% capacity, receiving continuous cross-region asynchronous database streaming replication and Kafka MirrorMaker 2 topic mirroring.
* **Edge Anycast Failover:** Cloudflare / Route53 monitors health and shifts traffic in $< 30$ seconds.
* **Elastic Surge Capacity:** KEDA scales microservices from 25% to 100% in $< 45$ seconds upon traffic ingress.

### Positive Consequences
* RTO guaranteed at $< 15$ minutes and RPO $< 1$ minute for Tier-1 services (`orders-service`, `keycloak`, PostgreSQL).
* Compute costs in the secondary region are capped at ~25% of the primary region during standard operations.
* Zero data split-brain risk due to asynchronous read-replica promotion semantics.

### Negative Consequences / Trade-offs
* Secondary database and cluster nodes incur baseline infrastructure expenditure.
* Failback requires a planned maintenance window to resynchronize delta state back to the primary region without dual-master conflicts.

---

## 🛡️ Security & Operational Validation
* **Continuous Monitoring:** Edge probes test both primary and secondary Ingress endpoints every 5 seconds.
* **Velero Backups:** Scheduled daily backups of Kubernetes secrets and configurations to S3 with Object Lock.
* **GameDays:** Semi-annual simulated regional disaster drills to measure actual RTO/RPO against SLOs.
