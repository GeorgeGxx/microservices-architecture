# 📄 ADR-[000]: [Short Title in Imperative Tense]

* **Status:** PROPOSED | ACCEPTED | DEPRECATED | SUPERSEDED
* **Deciders:** [Architecture Lead, Tech Lead, Product Owner, SecOps Lead]
* **Date:** YYYY-MM-DD
* **Technical Story / Jira Epic:** [PROJ-XXX]

---

## 🎯 Context & Problem Statement

Describe the context and the problem to be solved. What business or technical requirements necessitate this architectural decision? What constraints (e.g. latency, cost, security, compliance) apply?

---

## ⚖️ Decision Drivers

1. [Driver 1: e.g. Throughput and P99 Latency < 100ms]
2. [Driver 2: e.g. Open-Source vs Licensing / Cloud Vendor Lock-In]
3. [Driver 3: e.g. Operational Overhead and Team Expertise]
4. [Driver 4: e.g. Security, Zero-Trust, and Compliance]

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** [Description]
* **Option 2:** [Description]
* **Option 3:** [Description]

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1 (Baseline) | Option 2 | Option 3 |
| :--- | :---: | :---: | :---: | :---: |
| **Criteria 1** (e.g. Performance) | 5 | 0 (Baseline) | +1 / 0 / -1 | +1 / 0 / -1 |
| **Criteria 2** (e.g. Integration) | 4 | 0 (Baseline) | +1 / 0 / -1 | +1 / 0 / -1 |
| **Criteria 3** (e.g. Cost/Resource) | 3 | 0 (Baseline) | +1 / 0 / -1 | +1 / 0 / -1 |
| **Criteria 4** (e.g. Security) | 4 | 0 (Baseline) | +1 / 0 / -1 | +1 / 0 / -1 |
| **Weighted Total** | - | **0.00** | **[Score]** | **[Score]** |

*Scoring: +1 = Superior to baseline, 0 = Equal to baseline, -1 = Inferior to baseline.*

---

## 💡 Decision Outcome

Chosen option: **[Option X]**, because [justification summarizing the Pugh matrix outcome and alignment with business/technical goals].

### Positive Consequences
* [Positive consequence 1]
* [Positive consequence 2]

### Negative Consequences / Trade-offs
* [Negative consequence / known limitation and mitigation]

---

## 🛡️ Security & Operational Validation
* How will this decision be verified in the automated CI/CD pipeline? (e.g. k6 performance gate, Newman contract test, SonarQube quality gate).
