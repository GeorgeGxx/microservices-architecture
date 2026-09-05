# 🛡️ DevSecOps & Governance Hub

This directory centralizes all security, compliance, quality, and dynamic testing assets and policies for the `microservices-architecture` ecosystem.

---

## 📂 Directory Structure

```
devsecops/
├── dast/                      # 🕵️ Dynamic Application Security Testing (DAST)
│   └── zap/
│       ├── rules.tsv          # OWASP ZAP threshold calibration & alert overrides
│       └── zap-baseline.conf  # Execution parameters against Istio Ingress Gateway
│
├── policies/                  # 📜 Policy-as-Code (OPA / Rego)
│   ├── conftest/
│   │   └── kubernetes.rego    # Shift-Left: Pre-deployment Helm manifests audit (OPA v1)
│   └── gatekeeper/            # Admission Controller: Runtime enforcement on Minikube
│       ├── templates/         # ConstraintTemplates (Custom Rego CRDs)
│       └── constraints/       # Constraints applied to target namespaces (staging / prod)
│
├── sast/                      # 🔍 Static Application Security Testing (SAST & Secrets)
│   ├── gitleaks/
│   │   └── .gitleaks.toml     # Hardcoded secret, API key, and token detection
│   └── semgrep/               # Custom source code security rules
│
├── compliance/                # 🧰 Software Supply Chain Security
│   ├── trivy/
│   │   ├── trivy.yaml         # Container vulnerability scanner configuration
│   │   └── .trivyignore       # Formal risk acceptance and CVE exception registry
│   └── sbom/                  # Metadata schemas for CycloneDX / SPDX SBOMs
│
└── testing/                   # ⚡ Dynamic & Performance Testing
    ├── k6/
    │   └── load-test.js       # Stress testing & p95 latency SLO verification via Istio Gateway
    └── newman/
        └── microservices.postman_collection.json # API integration test suite
```

---

## ⚙️ Security Operating Modes: Audit vs. Enforce

| Tool | Current Mode (Audit / Soft-Gate) | Maturity Mode (Enforce / Hard-Gate) |
| :--- | :--- | :--- |
| **Trivy** | `--exit-code 0` (Reports vulnerabilities without breaking initial builds). | `--exit-code 1` (Blocks on any unpatched `CRITICAL` CVE not listed in `.trivyignore`). |
| **Gitleaks** | Blocking (`exit 1` on real credentials detection). | Blocking. |
| **Conftest (OPA)** | Blocking on privileged containers or missing memory/CPU limits. | Extended blocking (enforces mandatory labels, network policies). |
| **OWASP ZAP** | Fails on rules marked `FAIL` in `rules.tsv`; advisory on `WARN`. | Strict blocking on security headers and CSP violations. |
