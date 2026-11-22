# Jenkins CI/CD to AWS EKS with Helm

The root `Jenkinsfile` provides CI, DevSecOps checks, Docker Hub release publishing, and optional direct deployment to AWS EKS. It selects services with `scripts/release_service_detector.py`, runs service tests and repository security gates, then deploys signed immutable image digests through Helm. The deployment path uses AWS IAM and Kubernetes directly; it does not require Argo CD.

## Branch and environment mapping

| Branch | EKS cluster | Namespace | Production approval |
|---|---|---|---|
| `develop` | No AWS deployment; development remains on Minikube | — | No |
| `staging` | `msa-aws-staging` | `staging` | No |
| `master` | `msa-aws-prod` and `msa-aws-dp2-prod` | `production` | Jenkins `input` gate |

Pull request builds run validation only. Publishing is limited to the immutable Docker Hub tags `1.0.0` and `1.1.0`. The pipeline reuses an existing tag digest, blocks images with fixable critical vulnerabilities, signs newly published image digests with Cosign, and applies the repository's two-tag retention script. Publication is serialized per image repository. A deployment selects the full service matrix, so the umbrella release cannot unintentionally reset images for unselected services. Helm uses `--atomic --wait`; if a later deployment or post-deployment check fails, the pipeline restores the previous Helm revision on every target cluster.

Cloud deployment is disabled by default. `ENABLE_AWS_DEPLOY` and `DEPLOY` must both be selected explicitly. AWS deployment is limited to `staging` and `master`; `develop` is reserved for Minikube. Production approval occurs after image validation, publication, signing, and retention.

## Jenkins setup

Create a Multibranch Pipeline for this repository and enable branch discovery for `develop`, `staging`, and `master`, plus pull requests. Install the Pipeline Utility Steps, AnsiColor, Workspace Cleanup, and Lockable Resources plugins. Restrict who can approve the production `input` step using Jenkins job permissions and the organization's release-approver policy.

Use a trusted, isolated Linux agent labeled `linux-docker-devsecops`. It needs Docker with Buildx, Python 3.12, Java 21 and Maven, Node.js 24 and npm, Go, Helm 4, Conftest, Gitleaks, Semgrep, Trivy 0.76.1, TFLint, Terraform, AWS CLI v2, `kubectl`, `jq`, Cosign, and Snyk CLI when Snyk is enabled. The agent needs network access to Docker Hub, AWS APIs, EKS endpoints, and SonarCloud when enabled. Do not run untrusted pull request code on an agent with Docker credentials or cloud access.

Prefer an EC2 Jenkins agent instance profile or another short-lived AWS IAM identity. Do not configure long-lived AWS access keys. Grant the role only the required `eks:DescribeCluster` permission and authorize it in each target cluster through an EKS access entry (or the cluster's supported IAM authentication mechanism) mapped to namespace-scoped Kubernetes RBAC. The deployment role must be able to manage the Helm release and read workload readiness in the target namespace.

Configure these Jenkins credentials and environment variables:

| Jenkins credential / variable | Type | Use |
|---|---|---|
| `dockerhub-credentials` | Username with password | Docker Hub push and tag retention API |
| `cosign-private-key` | Secret file | Sign newly published OCI image digests |
| `cosign-password` | Secret text | Unlock the Cosign private key |
| `cosign-public-key` | Secret file | Verify the supply-chain manifest and image signatures before deployment |
| `sonar-token` | Secret text | SonarCloud analysis when `SONAR_ENABLED` is selected |
| `snyk-token` | Secret text | Snyk SCA when `SNYK_ENABLED` is selected |
| `AWS_ACCOUNT_ID` | Jenkins environment variable | Expected AWS account; deployment aborts if STS reports a different account |
| `AWS_REGION` | Jenkins environment variable | Defaults to `us-east-1` in the Jenkinsfile |
| `SONAR_ORGANIZATION` | Jenkins environment variable | SonarCloud organization key |
| `SONAR_HOST_URL` | Optional environment variable | Defaults to `https://sonarcloud.io` |
| `DEVSECOPS_BASE_URL` | Jenkins environment variable | API endpoint for post-deployment checks |
| `DEVSECOPS_FRONTEND_URL` | Jenkins environment variable | Frontend endpoint for smoke and DAST checks |
| `DEVSECOPS_KEYCLOAK_URL` | Jenkins environment variable | Keycloak endpoint for Newman tests |

## Running the pipeline

- Run a branch or pull request build with `PUBLISH_VERSION=none` for CI and security checks only.
- Choose `SERVICE_SCOPE=changed` for normal incremental work or `all` for a full platform run.
- For a release, select only `1.0.0` or `1.1.0`. The pipeline rejects pull request publication and deployment requests on non-environment branches.
- To deploy to AWS, select `ENABLE_AWS_DEPLOY=true` and `DEPLOY=true` on `staging` or `master`. The `master` build pauses for human approval before deploying to both production clusters.
- Select `POST_DEPLOY_ENABLED` to run Newman API contracts, storefront smoke checks, k6 load testing, and OWASP ZAP against the deployed release. Those endpoints must be configured in Jenkins first.

## Scope and operational notes

The pipeline runs language-specific service tests, Gitleaks, Semgrep, Trivy filesystem/configuration/image scans, Terraform formatting and TFLint checks, Helm rendering and Conftest policies, plus optional SonarCloud and Snyk analysis. It archives reports and coverage artifacts in Jenkins. AWS infrastructure provisioning remains outside this pipeline; Terraform is validated but not applied. Jenkins artifact retention, agent isolation, IAM permissions, EKS access entries, and production approval permissions must be configured by the Jenkins and AWS administrators.
