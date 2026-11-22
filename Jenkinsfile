pipeline {
    agent { label 'linux-docker-devsecops' }

    options {
        ansiColor('xterm')
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '10'))
        disableConcurrentBuilds(abortPrevious: false)
        skipDefaultCheckout(true)
        timestamps()
        timeout(time: 90, unit: 'MINUTES')
    }

    parameters {
        choice(name: 'SERVICE_SCOPE', choices: ['changed', 'all'], description: 'Services to validate and, when requested, publish.')
        choice(name: 'PUBLISH_VERSION', choices: ['none', '1.0.0', '1.1.0'], description: 'Immutable SemVer tag. “none” runs CI only.')
        booleanParam(name: 'SONAR_ENABLED', defaultValue: false, description: 'Run SonarCloud analysis; requires the sonar-token credential.')
        booleanParam(name: 'SNYK_ENABLED', defaultValue: false, description: 'Run Snyk SCA; requires the snyk-token credential and available quota.')
        booleanParam(name: 'ENABLE_AWS_DEPLOY', defaultValue: false, description: 'Enable direct AWS EKS access through IAM and Helm.')
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Deploy with Helm to the EKS cluster mapped to this branch.')
        booleanParam(name: 'POST_DEPLOY_ENABLED', defaultValue: false, description: 'Run Newman, smoke, k6, and OWASP ZAP against staging or production.')
    }

    environment {
        DOCKERHUB_OWNER = 'georgegxx'
        AWS_REGION = 'us-east-1'
        EKS_STAGING_CLUSTER = 'msa-aws-staging'
        EKS_PRODUCTION_CLUSTER = 'msa-aws-prod'
        EKS_PRODUCTION_DP2_CLUSTER = 'msa-aws-dp2-prod'
        HELM_VERSION = '4.3.1'
        SEMGREP_VERSION = '1.110.0'
    }

    stages {
        stage('Checkout and select services') {
            steps {
                deleteDir()
                checkout scm
                sh 'git fetch --no-tags origin +refs/heads/*:refs/remotes/origin/*'
                script {
                    def baseRef = env.CHANGE_TARGET ? "origin/${env.CHANGE_TARGET}" : (env.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: '')
                    if (!baseRef || sh(script: "git rev-parse --verify '${baseRef}^{commit}' >/dev/null 2>&1", returnStatus: true) != 0) {
                        baseRef = 'HEAD^'
                        if (sh(script: 'git rev-parse --verify HEAD^ >/dev/null 2>&1', returnStatus: true) != 0) {
                            baseRef = 'HEAD'
                        }
                    }

                    def selectorArgs = "--mode ci --base-ref '${baseRef}' --head-ref HEAD --matrix"
                    if (params.SERVICE_SCOPE == 'all' || params.DEPLOY) {
                        selectorArgs += ' --all'
                    }
                    def matrixJson = sh(
                        script: "python3 scripts/release_service_detector.py ${selectorArgs}",
                        returnStdout: true
                    ).trim()
                    env.SERVICE_MATRIX = matrixJson
                    env.SERVICE_NAMES = readJSON(text: matrixJson).collect { it['service-name'] }.join(',')
                    echo "Selected services: ${env.SERVICE_NAMES ?: '(none)'}"
                    if (params.DEPLOY && !params.ENABLE_AWS_DEPLOY) {
                        error('DEPLOY requires ENABLE_AWS_DEPLOY=true; stopping before image publication.')
                    }
                    if (params.DEPLOY && params.PUBLISH_VERSION == 'none') {
                        error('DEPLOY requires selecting immutable tag 1.0.0 or 1.1.0.')
                    }
                    if (params.POST_DEPLOY_ENABLED && !params.DEPLOY) {
                        error('POST_DEPLOY_ENABLED requires DEPLOY=true to test the deployed release.')
                    }
                    if (params.DEPLOY && !(env.BRANCH_NAME in ['staging', 'master'])) {
                        error('This AWS pipeline deploys only staging and master; develop is reserved for Minikube.')
                    }
                    if (params.PUBLISH_VERSION != 'none' && env.CHANGE_ID) {
                        error('Pull requests cannot publish images. Publish from develop, staging, or master.')
                    }
                }
            }
        }

        stage('Quality and security gates') {
            parallel {
                stage('Service tests') {
                    steps {
                        script {
                            def services = readJSON(text: env.SERVICE_MATRIX)
                            for (def service : services) {
                                def name = service['service-name']
                                def path = service['service-dir']
                                echo "Testing ${name} (${service['service-type']})"
                                switch (service['service-type']) {
                                    case 'spring-boot':
                                        dir(path) { sh 'mvn -B -T 1C clean test jacoco:report' }
                                        break
                                    case 'react':
                                    case 'frontend':
                                        dir(path) { sh 'npm ci && npm run test:coverage && npm run build' }
                                        break
                                    case 'go':
                                        dir(path) { sh 'go test -v -coverprofile=coverage.out ./...' }
                                        break
                                    case 'nestjs':
                                        dir(path) { sh 'npm ci && npm run typecheck && npm run test:cov && npm run build' }
                                        break
                                    case 'python':
                                        withEnv(["PYTHONPATH=${env.WORKSPACE}/${path}", "CI_SERVICE_NAME=${name}", "CI_SERVICE_DIR=${path}"]) {
                                            sh '''
                                                set -eu
                                                if [ -f "$CI_SERVICE_DIR/requirements.txt" ]; then
                                                  python3 -m pip install --disable-pip-version-check -r "$CI_SERVICE_DIR/requirements.txt"
                                                fi
                                                python3 -m pip install --disable-pip-version-check coverage pytest pytest-cov pytest-asyncio
                                                if [ -d "$CI_SERVICE_DIR/app" ]; then
                                                  (cd "$CI_SERVICE_DIR" && python3 -m pytest --cov=app --cov-report=xml:coverage.xml tests/ -v)
                                                elif [ -d "$CI_SERVICE_DIR/tests" ]; then
                                                  (cd "$CI_SERVICE_DIR" && python3 -m coverage run --source=. -m unittest discover -s tests -v && python3 -m coverage xml -o coverage.xml)
                                                fi
                                            '''
                                        }
                                        break
                                    case 'cosmo-router':
                                        sh 'npx --yes wgc@0.133.3 router compose --input cosmo-router/supergraph.yaml --out cosmo-router/execution-config.json'
                                        sh "bash scripts/install-helm4.sh v${env.HELM_VERSION}"
                                        sh 'helm lint helm/charts/cosmo-router && helm lint helm/microservices-umbrella --values helm/values/values-minikube.yaml'
                                        break
                                    default:
                                        error("Unsupported service type: ${service['service-type']}")
                                }
                            }
                        }
                    }
                }

                stage('Repository security scans') {
                    steps {
                        sh '''
                            set -eu
                            gitleaks git --redact --config devsecops/sast/gitleaks/.gitleaks.toml .
                            docker run --rm -v "$WORKSPACE:/src" -w /src \\
                              "returntocorp/semgrep:${SEMGREP_VERSION}" scan \\
                              --config devsecops/sast/semgrep/semgrep-rules.yaml \\
                              --config p/security-audit --severity ERROR --error --sarif --output semgrep-results.sarif .
                            trivy fs --config devsecops/compliance/trivy/trivy.yaml \\
                              --scanners vuln,misconfig,secret,license --format json --output trivy-fs-report.json .
                            trivy config --config devsecops/compliance/trivy/trivy.yaml \\
                              --exit-code 0 --format json --output trivy-iac-report.json terraform/
                            trivy --version | grep -F 'Version: 0.76.1'
                            gitleaks version
                            if [ -d terraform ]; then
                              terraform fmt -check -recursive terraform
                              tflint --chdir=terraform/environments/aws --init
                              tflint --chdir=terraform/environments/aws
                            fi
                        '''
                    }
                }

                stage('Helm policy checks') {
                    steps {
                        sh "bash scripts/install-helm4.sh v${env.HELM_VERSION}"
                        sh '''
                            set -eu
                            helm dependency build helm/microservices-umbrella
                            helm template microservices helm/microservices-umbrella \\
                              --values helm/values/values-eks-staging.yaml > rendered-staging.yaml
                            helm template microservices helm/microservices-umbrella \\
                              --values helm/values/values-eks-prod.yaml > rendered-production.yaml
                            conftest test rendered-staging.yaml --policy devsecops/policies/conftest/
                            conftest test rendered-production.yaml --policy devsecops/policies/conftest/
                        '''
                    }
                }
            }
        }

        stage('SonarCloud analysis') {
            when { expression { params.SONAR_ENABLED && !env.CHANGE_ID } }
            steps {
                script {
                    if (!env.SONAR_ORGANIZATION) {
                        error('Configure SONAR_ORGANIZATION in Jenkins before enabling SONAR_ENABLED.')
                    }
                    def services = readJSON(text: env.SERVICE_MATRIX)
                    withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                        for (def service : services) {
                            def name = service['service-name']
                            def path = service['service-dir']
                            withEnv(["SONAR_SERVICE=${name}"]) {
                                switch (service['service-type']) {
                                    case 'spring-boot':
                                        dir(path) {
                                            sh '''
                                                mvn -B -T 1C org.sonarsource.scanner.maven:sonar-maven-plugin:5.2.0.4988:sonar \\
                                                  -Dsonar.projectKey="msa-${SONAR_SERVICE}" -Dsonar.projectName="MSA ${SONAR_SERVICE}" \\
                                                  -Dsonar.organization="$SONAR_ORGANIZATION" \\
                                                  -Dsonar.host.url="${SONAR_HOST_URL:-https://sonarcloud.io}" \\
                                                  -Dsonar.java.binaries=target/classes -Dsonar.java.test.binaries=target/test-classes \\
                                                  -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml \\
                                                  -Dsonar.qualitygate.wait=true
                                            '''
                                        }
                                        break
                                    case 'react':
                                    case 'frontend':
                                        dir(path) {
                                            sh '''
                                                npx --yes sonarqube-scanner \\
                                                  -Dsonar.projectKey=msa-frontend -Dsonar.projectName="Novashop Storefront" \\
                                                  -Dsonar.organization="$SONAR_ORGANIZATION" \\
                                                  -Dsonar.host.url="${SONAR_HOST_URL:-https://sonarcloud.io}" \\
                                                  -Dsonar.sources=src -Dsonar.exclusions='**/*.test.ts,**/*.test.tsx' \\
                                                  -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \\
                                                  -Dsonar.qualitygate.wait=true
                                            '''
                                        }
                                        break
                                    case 'nestjs':
                                        dir(path) {
                                            sh '''
                                                npx --yes sonarqube-scanner \\
                                                  -Dsonar.projectKey="msa-${SONAR_SERVICE}" -Dsonar.projectName="MSA ${SONAR_SERVICE}" \\
                                                  -Dsonar.organization="$SONAR_ORGANIZATION" \\
                                                  -Dsonar.host.url="${SONAR_HOST_URL:-https://sonarcloud.io}" \\
                                                  -Dsonar.sources=src -Dsonar.tests=src -Dsonar.test.inclusions='**/*.spec.ts' \\
                                                  -Dsonar.exclusions='**/*.spec.ts,dist/**,node_modules/**' \\
                                                  -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \\
                                                  -Dsonar.qualitygate.wait=true
                                            '''
                                        }
                                        break
                                    case 'go':
                                        dir(path) {
                                            sh '''
                                                npx --yes sonarqube-scanner \\
                                                  -Dsonar.projectKey="msa-${SONAR_SERVICE}" -Dsonar.projectName="MSA ${SONAR_SERVICE}" \\
                                                  -Dsonar.organization="$SONAR_ORGANIZATION" \\
                                                  -Dsonar.host.url="${SONAR_HOST_URL:-https://sonarcloud.io}" \\
                                                  -Dsonar.sources=. -Dsonar.tests=. -Dsonar.test.inclusions='**/*_test.go' \\
                                                  -Dsonar.exclusions='**/*_test.go,docs/**,scripts/**' \\
                                                  -Dsonar.go.coverage.reportPaths=coverage.out -Dsonar.qualitygate.wait=true
                                            '''
                                        }
                                        break
                                    case 'python':
                                        dir(path) {
                                            sh '''
                                                npx --yes sonarqube-scanner \\
                                                  -Dsonar.projectKey="msa-${SONAR_SERVICE}" -Dsonar.projectName="MSA ${SONAR_SERVICE}" \\
                                                  -Dsonar.organization="$SONAR_ORGANIZATION" \\
                                                  -Dsonar.host.url="${SONAR_HOST_URL:-https://sonarcloud.io}" \\
                                                  -Dsonar.sources=. -Dsonar.tests=tests \\
                                                  -Dsonar.exclusions='tests/**,data/**,Dockerfile*,.venv*/**' \\
                                                  -Dsonar.python.version=3.12 -Dsonar.python.coverage.reportPaths=coverage.xml \\
                                                  -Dsonar.qualitygate.wait=true
                                            '''
                                        }
                                        break
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Snyk software composition analysis') {
            when { expression { params.SNYK_ENABLED } }
            steps {
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh '''
                        set -eu
                        snyk --version
                        snyk test --all-projects --severity-threshold=high --json-file-output=snyk-report.json
                    '''
                }
            }
        }

        stage('Build, scan and publish immutable images') {
            when {
                allOf {
                    expression { params.PUBLISH_VERSION in ['1.0.0', '1.1.0'] }
                    expression { !env.CHANGE_ID }
                    expression { env.BRANCH_NAME in ['develop', 'staging', 'master'] }
                }
            }
            steps {
                script {
                    def services = readJSON(text: env.SERVICE_MATRIX)
                    def releaseServices = services.findAll { it['service-name'] != 'cosmo-router' }
                    if (releaseServices.isEmpty()) {
                        error('No publishable images were found in the selected scope.')
                    }
                    withCredentials([
                        usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_TOKEN'),
                        file(credentialsId: 'cosign-private-key', variable: 'COSIGN_PRIVATE_KEY_FILE'),
                        string(credentialsId: 'cosign-password', variable: 'COSIGN_PASSWORD')
                    ]) {
                        sh 'printf "%s" "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USERNAME" --password-stdin'
                        for (def service : releaseServices) {
                            def name = service['service-name']
                            def dockerfile = service['dockerfile-path'] ?: "${service['service-dir']}/Dockerfile"
                            def context = service['context-dir'] ?: service['service-dir']
                            def image = "${env.DOCKERHUB_OWNER}/${name}:${params.PUBLISH_VERSION}"
                            lock(resource: "dockerhub-${env.DOCKERHUB_OWNER}-${name}") {
                                withEnv(["RELEASE_IMAGE=${image}", "RELEASE_DOCKERFILE=${dockerfile}", "RELEASE_CONTEXT=${context}", "RELEASE_SBOM=sbom-${name}.cdx.json"]) {
                                    sh '''
                                    set -eu
                                    existing="$(docker buildx imagetools inspect "$RELEASE_IMAGE" 2>/dev/null | awk '/^Digest:/ {print $2; exit}' || true)"
                                    if printf '%s' "$existing" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
                                      digest="$existing"
                                      echo "Reusing immutable tag $RELEASE_IMAGE@$digest"
                                    else
                                      docker buildx build --load --file "$RELEASE_DOCKERFILE" \\
                                        --tag "$RELEASE_IMAGE" "$RELEASE_CONTEXT"
                                      digest=''
                                    fi
                                    trivy image --config devsecops/compliance/trivy/trivy.yaml \\
                                      --ignore-unfixed --severity CRITICAL --exit-code 1 "$RELEASE_IMAGE"
                                    trivy image --config devsecops/compliance/trivy/trivy.yaml \\
                                      --ignore-unfixed --severity HIGH --exit-code 0 "$RELEASE_IMAGE"
                                    trivy image --format cyclonedx --output "$RELEASE_SBOM" "$RELEASE_IMAGE"
                                    if [ -z "$digest" ]; then
                                      docker push "$RELEASE_IMAGE"
                                      digest="$(docker buildx imagetools inspect "$RELEASE_IMAGE" | awk '/^Digest:/ {print $2; exit}')"
                                      cosign sign --yes --key "$COSIGN_PRIVATE_KEY_FILE" "$RELEASE_IMAGE@$digest"
                                    fi
                                    printf '%s\t%s\n' "$RELEASE_IMAGE" "$digest" >> release-digests.tsv
                                    '''
                                }
                            }
                        }
                        sh 'docker logout'
                    }
                    archiveArtifacts artifacts: 'release-digests.tsv', fingerprint: true
                    archiveArtifacts artifacts: 'sbom-*.cdx.json', allowEmptyArchive: false, fingerprint: true
                }
            }
        }

        stage('Retain active and rollback tags') {
            when { expression { params.PUBLISH_VERSION in ['1.0.0', '1.1.0'] && !env.CHANGE_ID } }
            steps {
                script {
                    def services = readJSON(text: env.SERVICE_MATRIX).findAll { it['service-name'] != 'cosmo-router' }
                    withCredentials([usernamePassword(credentialsId: 'dockerhub-credentials', usernameVariable: 'DOCKERHUB_USERNAME', passwordVariable: 'DOCKERHUB_TOKEN')]) {
                        for (def service : services) {
                            lock(resource: "dockerhub-${env.DOCKERHUB_OWNER}-${service['service-name']}") {
                                withEnv(["RETENTION_SERVICE=${service['service-name']}"]) {
                                    sh 'bash scripts/prune-dockerhub-tags.sh "$DOCKERHUB_OWNER" "$RETENTION_SERVICE"'
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Approve production deployment') {
            when {
                allOf {
                    expression { params.DEPLOY && env.BRANCH_NAME == 'master' }
                    expression { params.PUBLISH_VERSION in ['1.0.0', '1.1.0'] }
                }
            }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input message: "Approve deployment of ${params.PUBLISH_VERSION} to AWS EKS production (DP1 and DP2)?", ok: 'Approve production'
                }
            }
        }

        stage('Deploy to AWS EKS with Helm') {
            when {
                allOf {
                    expression { params.DEPLOY }
                    expression { params.PUBLISH_VERSION in ['1.0.0', '1.1.0'] }
                    expression { !env.CHANGE_ID }
                    expression { env.BRANCH_NAME in ['staging', 'master'] }
                }
            }
            steps {
                script {
                    if (!params.ENABLE_AWS_DEPLOY) {
                        error('Deployment blocked: enable ENABLE_AWS_DEPLOY together with DEPLOY.')
                    }
                    def services = readJSON(text: env.SERVICE_MATRIX).findAll { it['service-name'] != 'cosmo-router' }
                    def releaseDigests = readFile('release-digests.tsv').readLines().collectEntries { line ->
                        def columns = line.split('\\t', 2)
                        [(columns[0]): columns[1]]
                    }
                    def helmOverrides = []
                    def hasMlops = false
                    services.each { service ->
                        def name = service['service-name']
                        def image = "${env.DOCKERHUB_OWNER}/${name}:${params.PUBLISH_VERSION}"
                        def digest = releaseDigests[image]
                        if (!(digest ==~ /sha256:[0-9a-f]{64}/)) {
                            error("No validated immutable digest was found for ${image}.")
                        }
                        def valuesKey = [
                            'demand-forecast': 'mlops.forecast',
                            'mlops-training': 'mlops.training',
                            'mlflow': 'mlops.mlflow'
                        ].get(name, name)
                        if (name in ['demand-forecast', 'mlops-training', 'mlflow']) {
                            hasMlops = true
                        }
                        helmOverrides << "--set-string ${valuesKey}.image.repository=${env.DOCKERHUB_OWNER}/${name}"
                        helmOverrides << "--set-string ${valuesKey}.image.digest=${digest}"
                    }

                    def targetEnvironment = env.BRANCH_NAME == 'staging' ? 'staging' : 'prod'
                    def targetNamespace = env.BRANCH_NAME == 'staging' ? 'staging' : 'production'
                    def clusters = env.BRANCH_NAME == 'staging' ? [env.EKS_STAGING_CLUSTER] :
                        [env.EKS_PRODUCTION_CLUSTER, env.EKS_PRODUCTION_DP2_CLUSTER]
                    if (hasMlops) {
                        helmOverrides << "--set mlops.enabled=true"
                    }
                    withCredentials([file(credentialsId: 'cosign-public-key', variable: 'COSIGN_PUBLIC_KEY_FILE')]) {
                        withEnv([
                            "TARGET_ENVIRONMENT=${targetEnvironment}",
                            "TARGET_NAMESPACE=${targetNamespace}",
                            "TARGET_VALUES=helm/values/values-eks-${targetEnvironment}.yaml",
                            "EKS_TARGET_CLUSTERS=${clusters.join(' ')}",
                            "HELM_IMAGE_OVERRIDES=${helmOverrides.join(' ')}",
                            "DOCKERHUB_SERVICES=${services.collect { it['service-name'] }.join(' ')}"
                        ]) {
                            sh '''
                                set -eu
                                : "${AWS_ACCOUNT_ID:?Configure the expected AWS_ACCOUNT_ID in Jenkins}"
                                actual_account="$(aws sts get-caller-identity --query Account --output text)"
                                [ "$actual_account" = "$AWS_ACCOUNT_ID" ] || {
                                  echo "AWS account mismatch; refusing EKS deployment." >&2
                                  exit 1
                                }
                                cosign verify-blob --key "$COSIGN_PUBLIC_KEY_FILE" \\
                                  --bundle devsecops/compliance/cosign/supply-chain-manifest.sigstore.json \\
                                  --insecure-ignore-tlog=true devsecops/compliance/cosign/supply-chain-manifest.json
                                rollback_state='[]'
                                printf '%s\n' "$rollback_state" > rollback-state.json
                                for cluster in $EKS_TARGET_CLUSTERS; do
                                  aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster" --alias "$cluster"
                                  kubectl get nodes --request-timeout=20s
                                  previous_revision="$(helm history microservices --namespace "$TARGET_NAMESPACE" --output json 2>/dev/null | jq -r '.[-1].revision // 0' || printf '0')"
                                  rollback_state="$(jq -cn --argjson state "$rollback_state" --arg cluster "$cluster" --arg namespace "$TARGET_NAMESPACE" --argjson revision "$previous_revision" '$state + [{cluster: $cluster, namespace: $namespace, revision: $revision}]')"
                                  printf '%s\n' "$rollback_state" > rollback-state.json
                                done
                                for cluster in $EKS_TARGET_CLUSTERS; do
                                  aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster" --alias "$cluster"
                                  for service in $DOCKERHUB_SERVICES; do
                                    image="${DOCKERHUB_OWNER}/${service}:${PUBLISH_VERSION}"
                                    digest="$(awk -F '\t' -v image="$image" '$1 == image {print $2}' release-digests.tsv)"
                                    printf '%s' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' || {
                                      echo "Missing immutable image digest for $image" >&2
                                      exit 1
                                    }
                                    cosign verify --key "$COSIGN_PUBLIC_KEY_FILE" "$DOCKERHUB_OWNER/$service@$digest"
                                  done
                                  helm template microservices helm/microservices-umbrella \\
                                    --namespace "$TARGET_NAMESPACE" --values "$TARGET_VALUES" \\
                                    --set-string global.environment="$TARGET_ENVIRONMENT" $HELM_IMAGE_OVERRIDES \\
                                    > "rendered-${cluster}.yaml"
                                  conftest test "rendered-${cluster}.yaml" --policy devsecops/policies/conftest/
                                  helm upgrade --install microservices helm/microservices-umbrella \\
                                    --namespace "$TARGET_NAMESPACE" --create-namespace \\
                                    --values "$TARGET_VALUES" \\
                                    --set-string global.environment="$TARGET_ENVIRONMENT" \\
                                    $HELM_IMAGE_OVERRIDES --atomic --wait --timeout 10m
                                  kubectl wait --for=condition=Available deployment --all \\
                                    --namespace "$TARGET_NAMESPACE" --timeout=10m
                                done
                            '''
                        }
                    }
                }
            }
        }

        stage('Post-deployment assurance: API, SLO and DAST') {
            when {
                allOf {
                    expression { params.POST_DEPLOY_ENABLED && params.DEPLOY }
                    expression { params.PUBLISH_VERSION in ['1.0.0', '1.1.0'] }
                    expression { env.BRANCH_NAME in ['staging', 'master'] }
                }
            }
            steps {
                sh '''
                    set -eu
                    : "${DEVSECOPS_BASE_URL:?Configure DEVSECOPS_BASE_URL in Jenkins}"
                    : "${DEVSECOPS_FRONTEND_URL:?Configure DEVSECOPS_FRONTEND_URL in Jenkins}"
                    : "${DEVSECOPS_KEYCLOAK_URL:?Configure DEVSECOPS_KEYCLOAK_URL in Jenkins}"
                    npx --yes newman@6 run devsecops/testing/newman/microservices.postman_collection.json \\
                      --env-var "BASE_URL=$DEVSECOPS_BASE_URL" \\
                      --env-var "keycloak_url=$DEVSECOPS_KEYCLOAK_URL" --bail
                    python3 scripts/testing/smoke.py --deployment \\
                      --base-url "$DEVSECOPS_BASE_URL" --frontend-url "$DEVSECOPS_FRONTEND_URL"
                    docker run --rm --network host -v "$WORKSPACE:/workspace:ro" \\
                      grafana/k6:1.8.1 run --env "TARGET_URL=$DEVSECOPS_BASE_URL" \\
                      /workspace/devsecops/testing/k6/load-test.js
                    mkdir -p artifacts/zap
                    docker run --rm --network host \\
                      -v "$WORKSPACE/devsecops/dast/zap:/zap/rules:ro" \\
                      -v "$WORKSPACE/artifacts/zap:/zap/wrk:rw" \\
                      ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \\
                      -t "$DEVSECOPS_FRONTEND_URL" -c /zap/rules/rules.tsv -r zap-report.html -I
                '''
            }
        }
    }

    post {
        always {
            sh 'docker logout >/dev/null 2>&1 || true'
            archiveArtifacts artifacts: 'rendered-*.yaml,release-digests.tsv,rollback-state.json,sbom-*.cdx.json,semgrep-results.sarif,trivy-*-report.json,snyk-report.json,artifacts/zap/zap-report.html,**/coverage.xml,**/coverage.out,**/lcov.info,**/jacoco.xml', allowEmptyArchive: true, fingerprint: true
        }
        failure {
            echo 'Pipeline failed. Review the gates before retrying publication or deployment.'
            script {
                if (params.DEPLOY && fileExists('rollback-state.json') && env.BRANCH_NAME in ['staging', 'master']) {
                    def rollbackTargets = readJSON(file: 'rollback-state.json')
                    withEnv(["ROLLBACK_TARGETS=${rollbackTargets.collect { "${it.cluster}:${it.namespace}:${it.revision}" }.join(' ')}"]) {
                        sh '''
                            set -eu
                            for target in $ROLLBACK_TARGETS; do
                              IFS=: read -r cluster namespace revision <<EOF
$target
EOF
                              aws eks update-kubeconfig --region "$AWS_REGION" --name "$cluster" --alias "$cluster"
                              if [ "$revision" -gt 0 ]; then
                                echo "Rolling back Helm release in $cluster/$namespace to revision $revision"
                                helm rollback microservices "$revision" --namespace "$namespace" --wait --timeout 10m
                              else
                                echo "Removing first-time failed Helm release in $cluster/$namespace"
                                helm uninstall microservices --namespace "$namespace" --wait || true
                              fi
                            done
                        '''
                    }
                }
            }
        }
        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}
