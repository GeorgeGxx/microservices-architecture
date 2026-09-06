import xml.etree.ElementTree as ET

def build_drawio_xml():
    root_mxfile = ET.Element("mxfile", host="Electron", pages="8", type="device")

    # Helper function to create page
    def create_page(page_id, page_name):
        diagram = ET.SubElement(root_mxfile, "diagram", id=page_id, name=page_name)
        model = ET.SubElement(diagram, "mxGraphModel", dx="2000", dy="1200", grid="1", gridSize="10", guides="1", tooltips="1", connect="1", arrows="1", fold="1", page="1", pageScale="1", pageWidth="1920", pageHeight="1080", math="0", shadow="0")
        root = ET.SubElement(model, "root")
        ET.SubElement(root, "mxCell", id="0")
        ET.SubElement(root, "mxCell", id="1", parent="0")
        return root

    def add_node(root, cell_id, parent_id, value, style, x, y, w, h):
        cell = ET.SubElement(root, "mxCell", id=cell_id, parent=parent_id, value=value, style=style, vertex="1")
        ET.SubElement(cell, "mxGeometry", {"x": str(x), "y": str(y), "width": str(w), "height": str(h), "as": "geometry"})
        return cell

    def add_edge(root, cell_id, parent_id, value, style, source_id, target_id, points=None):
        cell = ET.SubElement(root, "mxCell", id=cell_id, parent=parent_id, value=value, style=style, edge="1", source=source_id, target=target_id)
        geom = ET.SubElement(cell, "mxGeometry", {"relative": "1", "as": "geometry"})
        if points:
            arr = ET.SubElement(geom, "Array", {"as": "points"})
            for pt in points:
                ET.SubElement(arr, "mxPoint", x=str(pt[0]), y=str(pt[1]))
        return cell

    title_style = "text;html=1;align=center;verticalAlign=middle;rounded=0;"

    # =========================================================================
    # PAGE 1: General Architecture & Microservices
    # =========================================================================
    r1 = create_page("page_general_arch", "1. General Architecture & Microservices")
    
    # Title
    add_node(r1, "t1", "1", "<b style='font-size:22px;color:#1E293B;'>ECOMMERCE - MICROSERVICES ARCHITECTURE OVERVIEW</b><br><span style='font-size:13px;color:#64748B;'>Spring Boot 3.4 • Angular 21 • Keycloak 26 • Kafka KRaft • Istio Mesh • HashiCorp Vault • Full-Stack Observability</span>", title_style, 300, 30, 1200, 50)

    # Client Layer
    add_node(r1, "c_client", "1", "<b>🌐 CLIENT LAYER</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 110, 340, 420)
    add_node(r1, "n_spa", "1", "<b>Angular 21 SPA</b><br>Storefront UI (Port 4200)<br>PKCE Flow & Token Storage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 170, 280, 70)
    add_node(r1, "n_traffic", "1", "<b>Traffic Simulator</b><br>simulate-traffic.py<br>Load & E2E Purchase Flow", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 270, 280, 70)
    add_node(r1, "n_postman", "1", "<b>Postman / API Clients</b><br>Swagger UI & OpenAPI Docs<br>/v3/api-docs", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 370, 280, 70)

    # Edge / Gateway & Security
    add_node(r1, "c_edge", "1", "<b>🛡️ EDGE & IDENTITY LAYER</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 440, 110, 380, 420)
    add_node(r1, "n_gw", "1", "<b>Spring Cloud API Gateway</b><br>Port 8080<br>JWT Validation • Rate Limiting<br>Token Relay • Circuit Breakers", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=12;", 470, 170, 320, 80)
    add_node(r1, "n_kc", "1", "<b>Keycloak 26 (IAM)</b><br>Port 8181 (OIDC / OAuth2)<br>Realm: microservices-realm<br>Self-Registration • Default USER Role<br>Users / Roles / PKCE", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=12;", 470, 280, 320, 80)
    add_node(r1, "n_db_kc", "1", "<b>PostgreSQL Keycloak</b><br>db-keycloak (Port 5434)<br>Persistent Realm Database", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=1.5;fontColor=#831843;fontSize=11;", 550, 400, 160, 70)

    # Microservices Backend Layer
    add_node(r1, "c_ms", "1", "<b>📦 CORE MICROSERVICES LAYER (Spring Boot 3.4 / Java 21)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 860, 110, 520, 780)
    add_node(r1, "n_prod", "1", "<b>Products Service</b><br>Port 8004<br>Catalog Management • Redis Cache", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 170, 220, 80)
    add_node(r1, "n_orders", "1", "<b>Orders Service</b><br>Port 8003<br>Saga Coordinator • Resilience4j<br>Multi-Tenant User Isolation (JWT sub)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 350, 220, 80)
    add_node(r1, "n_inv", "1", "<b>Inventory Service</b><br>Port 8001<br>Stock Validation • Lock/Deduct", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 530, 220, 80)
    add_node(r1, "n_notif", "1", "<b>Notification Service</b><br>Port 8002<br>Email Dispatcher • Event Consumer", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 710, 220, 80)

    # Persistence Layer
    add_node(r1, "n_db_prod", "1", "<b>db-products</b><br>PostgreSQL 16<br>Port 5433", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 175, 160, 70)
    add_node(r1, "n_db_orders", "1", "<b>db-orders</b><br>PostgreSQL 16<br>Port 5432", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 355, 160, 70)
    add_node(r1, "n_db_inv", "1", "<b>db-inventory</b><br>PostgreSQL 16<br>Port 5431", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 535, 160, 70)

    # Async Event Streaming & Cache
    add_node(r1, "c_async", "1", "<b>⚡ EVENT STREAMING & CACHE</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 1420, 110, 440, 340)
    add_node(r1, "n_kafka", "1", "<b>Apache Kafka 7.8 (KRaft)</b><br>kafka:9094 (SASL_PLAINTEXT) • kafka:9092<br>Topics: orders-topic, orders-topic-dlt", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=12;", 1450, 170, 380, 80)
    add_node(r1, "n_redis", "1", "<b>Redis 8.8 (Cache & Rate Limiting)</b><br>redis:6379<br>Products & Session Caching", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;strokeWidth=2;fontColor=#7F1D1D;fontSize=12;", 1450, 290, 380, 80)

    # Security & Secret Management Layer (Vault)
    add_node(r1, "c_vault", "1", "<b>🔒 ENTERPRISE SECURITY (HashiCorp Vault)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 570, 760, 320)
    add_node(r1, "n_vault", "1", "<b>HashiCorp Vault v2.0.4</b><br>Port 8200 (Dev/Prod Engine)<br>KV-v2 Secrets • Dynamic DB Credentials<br>Transit Encryption • Audit Device Logging", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;", 90, 630, 340, 90)
    add_node(r1, "n_vault_init", "1", "<b>vault-init (Zero-Touch Seeder)</b><br>Ephemeral Startup Container<br>Seeds DB passwords, Keycloak Secrets,<br>Kafka configs & Least-Privilege Policies", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;", 460, 630, 330, 90)
    add_node(r1, "n_eso", "1", "<b>External Secrets Operator (ESO)</b><br>K8s SecretStore & ExternalSecret<br>Syncs Vault -> Native K8s Secrets", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=11;", 90, 760, 340, 70)
    add_node(r1, "n_pki", "1", "<b>Vault PKI Plug-in CA</b><br>Intermediate CA -> istio-system/cacerts<br>Signs Istio Zero-Trust mTLS Mesh", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=11;", 460, 760, 330, 70)

    # Observability Stack
    add_node(r1, "c_obs", "1", "<b>📊 FULL-STACK OBSERVABILITY & TELEMETRY</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 1420, 480, 440, 410)
    add_node(r1, "n_otel", "1", "<b>OpenTelemetry Collector</b><br>OTLP Receiver (Port 4317 / 4318)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;strokeWidth=1.5;fontColor=#0C4A6E;fontSize=11;", 1450, 540, 180, 60)
    add_node(r1, "n_alloy", "1", "<b>Grafana Alloy (Logs/Traces)</b><br>Collector & Pipeline Processor", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;strokeWidth=1.5;fontColor=#0C4A6E;fontSize=11;", 1650, 540, 180, 60)
    add_node(r1, "n_prom", "1", "<b>Prometheus v3</b><br>Metrics Store (9090)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;strokeWidth=1.5;fontColor=#0C4A6E;fontSize=11;", 1450, 630, 180, 60)
    add_node(r1, "n_loki", "1", "<b>Grafana Loki</b><br>Log Aggregation (3100)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;strokeWidth=1.5;fontColor=#0C4A6E;fontSize=11;", 1650, 630, 180, 60)
    add_node(r1, "n_tempo", "1", "<b>Grafana Tempo</b><br>Distributed Tracing (3200)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;strokeWidth=1.5;fontColor=#0C4A6E;fontSize=11;", 1450, 720, 180, 60)
    add_node(r1, "n_grafana", "1", "<b>Grafana Dashboard</b><br>Port 3000 (Unified Master UI)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFEDD5;strokeColor=#F97316;strokeWidth=2;fontColor=#7C2D12;fontSize=12;", 1650, 720, 180, 60)

    # Connections
    add_edge(r1, "e1", "1", "HTTP / OIDC", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#3B82F6;strokeWidth=2;", "n_spa", "n_gw")
    add_edge(r1, "e2", "1", "Auth Check / JWKS", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#EC4899;strokeWidth=2;", "n_gw", "n_kc")
    add_edge(r1, "e3", "1", "mTLS / Bearer Token", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#6366F1;strokeWidth=2;", "n_gw", "n_prod")
    add_edge(r1, "e4", "1", "mTLS / Bearer Token", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#6366F1;strokeWidth=2;", "n_gw", "n_orders")
    add_edge(r1, "e5", "1", "Stock Check", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#10B981;strokeWidth=2;", "n_orders", "n_inv")
    add_edge(r1, "e6", "1", "Publish (SASL 9094)", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#F59E0B;strokeWidth=2;", "n_orders", "n_kafka")
    add_edge(r1, "e7", "1", "Consume (SASL 9094)", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#F59E0B;strokeWidth=2;", "n_kafka", "n_notif")
    add_edge(r1, "e8", "1", "JDBC", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_prod", "n_db_prod")
    add_edge(r1, "e9", "1", "JDBC", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_orders", "n_db_orders")
    add_edge(r1, "e10", "1", "JDBC", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_inv", "n_db_inv")
    add_edge(r1, "e11", "1", "Zero-Touch Seed", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#A855F7;strokeWidth=2;", "n_vault_init", "n_vault")
    add_edge(r1, "e12", "1", "Inject Secrets", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#A855F7;strokeWidth=2;dashed=1;", "n_vault", "n_orders")

    # =========================================================================
    # PAGE 2: HashiCorp Vault - Zero-Touch Security Architecture
    # =========================================================================
    r2 = create_page("page_vault_arch", "2. HashiCorp Vault - Zero-Touch Security Architecture")
    add_node(r2, "t2", "1", "<b style='font-size:22px;color:#1E293B;'>HASHICORP VAULT - ZERO-TOUCH ENTERPRISE SECURITY ARCHITECTURE</b><br><span style='font-size:13px;color:#64748B;'>Automated provisioning, least-privilege policy isolation, and advanced cryptographic engines</span>", title_style, 300, 30, 1200, 50)

    add_node(r2, "v_box_init", "1", "<b>1. STARTUP PHASE (Zero-Touch)</b><br>compose.yaml: vault-init container<br>• Waits for Vault to be healthy<br>• Enables KV-v2, Transit, Database, Audit<br>• Seeds microservices credentials<br>• Exits cleanly (exit 0)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;align=left;spacingLeft=15;", 100, 120, 380, 140)
    add_node(r2, "v_box_server", "1", "<b>2. HASHICORP VAULT SERVER</b><br>Core Security Engine (Port 8200)<br>• Token & Kubernetes Authentication<br>• Policy Enforcement Engine<br>• Telemetry & Prometheus metrics<br>• Real-time Audit logging", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=12;align=left;spacingLeft=15;", 580, 120, 420, 140)

    # Engines inside Vault
    add_node(r2, "e_kv", "1", "<b>KV-v2 Secrets Engine</b><br>secret/application<br>secret/products-service<br>secret/orders-service<br>secret/inventory-service<br>secret/notification-service<br>secret/api-gateway", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=11;align=left;spacingLeft=10;", 100, 320, 240, 140)
    add_node(r2, "e_db", "1", "<b>Dynamic Database Engine</b><br>database/config/postgres-products<br>database/roles/products-db-role<br>• On-the-fly user creation<br>• Automatic 1h TTL<br>• Auto-drop on expiration", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;align=left;spacingLeft=10;", 380, 320, 280, 140)
    add_node(r2, "e_tr", "1", "<b>Transit Encryption Engine</b><br>transit/keys/microservices-data-key<br>• Encryption as a Service<br>• AES256-GCM96<br>• Protects Credit Cards & PII<br>• Zero app key storage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=11;align=left;spacingLeft=10;", 700, 320, 280, 140)
    add_node(r2, "e_pki", "1", "<b>PKI Certificate Engine</b><br>pki_int (Intermediate CA)<br>• Emits ca-cert.pem / root-cert.pem<br>• Signs istio-system/cacerts<br>• Zero-Trust mTLS Mesh Trust", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FCE7F3;strokeColor=#DB2777;strokeWidth=1.5;fontColor=#831843;fontSize=11;align=left;spacingLeft=10;", 1020, 320, 280, 140)

    # 4 Integration Approaches
    add_node(r2, "app_compose", "1", "<b>Approach A: Docker Compose</b><br>Default fast startup via .env<br>Zero friction, fallback guaranteed", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 100, 520, 280, 90)
    add_node(r2, "app_spring", "1", "<b>Approach B: Native Spring Boot</b><br>--spring.profiles.active=vault<br>application-vault.yml in all 5 apps<br>Spring Cloud Vault direct connection", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 420, 520, 300, 90)
    add_node(r2, "app_eso", "1", "<b>Approach C: External Secrets (ESO)</b><br>K8s SecretStore & ExternalSecret<br>Syncs to microservices-secrets<br>Zero sidecar RAM footprint (Recommended)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 760, 520, 320, 90)
    add_node(r2, "app_sidecar", "1", "<b>Approach D: Vault Agent Sidecar</b><br>vault.hashicorp.com/agent-inject<br>Injects /vault/secrets/database.env<br>Multi-Cloud production standard", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 1120, 520, 300, 90)

    # Least Privilege Policies
    add_node(r2, "pol_box", "1", "<b>LEAST-PRIVILEGE ACCESS POLICIES (Service-Level Isolation)</b><br>• <b>products-service-policy:</b> READ secret/data/products-service + secret/data/application<br>• <b>orders-service-policy:</b> READ secret/data/orders-service + secret/data/application<br>• <b>inventory-service-policy:</b> READ secret/data/inventory-service + secret/data/application<br>• <b>notification-service-policy:</b> READ secret/data/notification-service + secret/data/application<br>• <b>api-gateway-policy:</b> READ secret/data/api-gateway + secret/data/application", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=1.5;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 100, 660, 1320, 120)

    add_edge(r2, "ve1", "1", "Seeds All Engines", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#A855F7;strokeWidth=2;", "v_box_init", "v_box_server")
    add_edge(r2, "ve2", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "v_box_server", "e_kv")
    add_edge(r2, "ve3", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "v_box_server", "e_db")
    add_edge(r2, "ve4", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "v_box_server", "e_tr")
    add_edge(r2, "ve5", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "v_box_server", "e_pki")

    # =========================================================================
    # PAGE 3: Sequence - Dynamic Database Secret Rotation
    # =========================================================================
    r3 = create_page("page_rotation_seq", "3. Sequence - Dynamic Database Secret Rotation")
    add_node(r3, "t3", "1", "<b style='font-size:22px;color:#1E293B;'>DYNAMIC DATABASE SECRET ROTATION SEQUENCE</b><br><span style='font-size:13px;color:#64748B;'>Ephemeral user generation, automated revocation, and transparent lease renewals</span>", title_style, 300, 30, 1200, 50)

    # Sequence Actors
    add_node(r3, "act_docker", "1", "<b>1. Docker / K8s<br>Bootstrap</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E2E8F0;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=12;", 100, 110, 180, 50)
    add_node(r3, "act_pg", "1", "<b>2. PostgreSQL<br>(db-products)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 380, 110, 180, 50)
    add_node(r3, "act_vault", "1", "<b>3. HashiCorp<br>Vault Server</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;", 660, 110, 180, 50)
    add_node(r3, "act_ms", "1", "<b>4. Microservice<br>(products-service)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 940, 110, 180, 50)

    # Lifelines
    add_node(r3, "line_docker", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 190, 160, 10, 680)
    add_node(r3, "line_pg", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 470, 160, 10, 680)
    add_node(r3, "line_vault", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 750, 160, 10, 680)
    add_node(r3, "line_ms", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1030, 160, 10, 680)

    # Steps
    add_node(r3, "s1", "1", "1. Initialize DB with master admin credentials (postgres/postgres from .env)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#94A3B8;fontSize=11;align=left;spacingLeft=10;", 190, 200, 280, 40)
    add_node(r3, "s2", "1", "2. vault-init stores master connection in database/config/postgres-products", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#94A3B8;fontSize=11;align=left;spacingLeft=10;", 190, 270, 560, 40)
    add_node(r3, "s3", "1", "3. Microservice requests DB connection: GET database/creds/products-db-role", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;fontSize=11;align=left;spacingLeft=10;", 750, 340, 280, 40)
    add_node(r3, "s4", "1", "4. Vault executes in Postgres: CREATE ROLE 'v-token-prod-a1b2' PASSWORD 'X#9...' VALID UNTIL 1h", "rounded=1;whiteSpace=wrap;html=1;fillColor=#DCFCE7;strokeColor=#16A34A;fontSize=11;align=left;spacingLeft=10;", 470, 410, 280, 40)
    add_node(r3, "s5", "1", "5. Vault delivers dynamic user 'v-token-prod-a1b2' & temporary password (Lease TTL: 1h)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2FE;strokeColor=#0284C7;fontSize=11;align=left;spacingLeft=10;", 750, 480, 280, 40)
    add_node(r3, "s6", "1", "6. Microservice opens JDBC connection pool using the ephemeral user credentials", "rounded=1;whiteSpace=wrap;html=1;fillColor=#DCFCE7;strokeColor=#16A34A;fontSize=11;align=left;spacingLeft=10;", 470, 550, 560, 40)
    add_node(r3, "s7", "1", "⏰ <b>1 HOUR ELAPSES (Lease TTL Expiration)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;fontColor=#991B1B;fontSize=12;align=center;", 380, 620, 680, 35)
    add_node(r3, "s8", "1", "7. Vault destroys previous user in Postgres: DROP ROLE 'v-token-prod-a1b2'", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;fontSize=11;align=left;spacingLeft=10;", 470, 680, 280, 40)
    add_node(r3, "s9", "1", "8. Vault generates & issues new user 'v-token-prod-c3d4' with zero service downtime", "rounded=1;whiteSpace=wrap;html=1;fillColor=#DCFCE7;strokeColor=#16A34A;fontSize=11;align=left;spacingLeft=10;", 470, 750, 560, 40)

    # =========================================================================
    # PAGE 4: Istio Service Mesh & Zero-Trust mTLS
    # =========================================================================
    r4 = create_page("page_istio_mesh", "4. Istio Service Mesh & Zero-Trust mTLS")
    add_node(r4, "t4", "1", "<b style='font-size:22px;color:#1E293B;'>ISTIO SERVICE MESH - ZERO-TRUST MTLS & TRAFFIC SHAPING</b><br><span style='font-size:13px;color:#64748B;'>STRICT mTLS security with SPIFFE identities, Vault Intermediate CA, and progressive Canary releases</span>", title_style, 300, 30, 1200, 50)

    add_node(r4, "i_ingress", "1", "<b>🌐 ISTIO INGRESS GATEWAY</b><br>microservices-gateway (Port 80 / 443)<br>TLS Termination • Edge Routing to Mesh", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=12;", 100, 140, 320, 90)
    add_node(r4, "i_istiod", "1", "<b>🛡️ ISTIOD CONTROL PLANE</b><br>Citadel CA & Discovery Server<br>Mounted Secret: <b>istio-system/cacerts</b><br>(Signed by Vault PKI Intermediate CA)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#DB2777;strokeWidth=2;fontColor=#831843;fontSize=12;", 500, 140, 360, 90)

    add_node(r4, "i_mesh_box", "1", "<b>🔒 ZERO-TRUST SERVICE MESH (PeerAuthentication: STRICT mTLS)</b><br><span style='font-size:10px;color:#64748B;'>Actuator Scrape Ports (8080, 8001-8004): PERMISSIVE for Prometheus Scraping</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 100, 280, 1340, 480)

    add_node(r4, "pod_gw", "1", "<b>Pod: api-gateway</b><br>App Container (8080)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>spiffe://cluster.local/ns/ecommerce/sa/api-gateway</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 140, 350, 320, 90)
    add_node(r4, "pod_prod_v1", "1", "<b>Pod: products-service (v1 - 90%)</b><br>App Container (8004)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>spiffe://cluster.local/ns/ecommerce/sa/products-service</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 540, 350, 340, 90)
    add_node(r4, "pod_prod_v2", "1", "<b>Pod: products-service (v2 Canary - 10%)</b><br>App Container (8004)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>Canary Release (set-canary-weight.ps1)</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 960, 350, 340, 90)
    add_node(r4, "pod_orders", "1", "<b>Pod: orders-service</b><br>App Container (8003)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>Resilience4j Circuit Breaker & Outlier Detection</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 140, 520, 320, 90)
    add_node(r4, "pod_inv", "1", "<b>Pod: inventory-service</b><br>App Container (8001)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>Stock Validation & Lock Engine</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 540, 520, 340, 90)
    add_node(r4, "pod_notif", "1", "<b>Pod: notification-service</b><br>App Container (8002)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>Event Driven Consumer</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 960, 520, 340, 90)

    add_edge(r4, "ie1", "1", "Rotates X.509 certs (24h)", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#DB2777;strokeWidth=1.5;dashed=1;", "i_istiod", "pod_gw")
    add_edge(r4, "ie2", "1", "STRICT mTLS", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=2;", "pod_gw", "pod_prod_v1")
    add_edge(r4, "ie3", "1", "STRICT mTLS", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=2;", "pod_gw", "pod_orders")
    add_edge(r4, "ie4", "1", "STRICT mTLS", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=2;", "pod_orders", "pod_inv")

    # =========================================================================
    # PAGE 5: Secret Isolation & Configuration Precedence
    # =========================================================================
    r5 = create_page("page_precedence", "5. Secret Isolation & Configuration Precedence")
    add_node(r5, "t5", "1", "<b style='font-size:22px;color:#1E293B;'>CONFIGURATION PRECEDENCE & SECRET ISOLATION HIERARCHY</b><br><span style='font-size:13px;color:#64748B;'>Why zero collisions or race conditions exist between Spring Cloud Vault, Sidecar, ESO, and .env</span>", title_style, 300, 30, 1200, 50)

    add_node(r5, "p1", "1", "<b>LEVEL 1: Operating System Environment Variables (Highest Priority)</b><br>• Local <b>.env</b> file in Docker Compose<br>• Injected secrets from <b>Vault Agent Sidecar</b> (/vault/secrets/database.env)<br>• Standard Kubernetes Secret mounted via <b>External Secrets Operator (ESO)</b><br><i>Overrides any packaged or static application configuration.</i>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;align=left;spacingLeft=20;", 200, 130, 1100, 90)
    add_node(r5, "p2", "1", "<b>LEVEL 2: Active Profile Properties (application-vault.yml)</b><br>• Active <b>strictly</b> when passing <code>--spring.profiles.active=vault</code><br>• Connects directly via REST API to Vault Server to load secrets into JVM memory<br>• <i>If the 'vault' profile is not active, this bootstrap configuration remains totally inert.</i>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;align=left;spacingLeft=20;", 200, 260, 1100, 90)
    add_node(r5, "p3", "1", "<b>LEVEL 3: Base Application Properties (application.yml)</b><br>• Default fallback properties packaged inside the Spring Boot JAR<br>• Parameterized placeholders: <code>${SPRING_DATASOURCE_URL:...}</code><br>• Acts as a safe fallback when no environment variables or Vault profiles are supplied.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 200, 390, 1100, 90)

    add_node(r5, "p_conclusion", "1", "<b>🎯 ZERO-COLLISION ARCHITECTURAL GUARANTEE:</b><br>1. <b>Fast Local Development:</b> Run <code>docker compose up -d</code> (Reads .env directly with zero friction).<br>2. <b>Direct Java Vault Testing:</b> Run <code>mvn spring-boot:run -Dspring-boot.run.profiles=vault</code>.<br>3. <b>Kubernetes / Minikube:</b> Use <code>External Secrets Operator (ESO)</code> to sync secrets into K8s without code changes.<br>4. <b>Multi-Cloud Production:</b> Use <code>Vault Agent Sidecar</code> with KMS Auto-Unseal and Cloud Workload Identity / IRSA.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;align=left;spacingLeft=20;", 200, 520, 1100, 130)

    # =========================================================================
    # PAGE 6: Kubernetes & Minikube Cluster Topology
    # =========================================================================
    r6 = create_page("page_k8s_topo", "6. Kubernetes & Minikube Cluster Topology")
    add_node(r6, "t6", "1", "<b style='font-size:22px;color:#1E293B;'>KUBERNETES & MINIKUBE CLUSTER TOPOLOGY</b><br><span style='font-size:13px;color:#64748B;'>Namespace isolation, ServiceAccount identities, RBAC Auth Delegator, and Istio Service Mesh</span>", title_style, 300, 30, 1200, 50)

    # Namespaces
    add_node(r6, "ns_vault", "1", "<b>🔒 NAMESPACE: vault</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 80, 120, 380, 480)
    add_node(r6, "k_vault_pod", "1", "<b>Deployment: vault</b><br>hashicorp/vault:2.0.4<br>Service: vault:8200", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=12;", 110, 180, 320, 80)
    add_node(r6, "k_sa_vault", "1", "<b>ServiceAccount: vault-auth</b><br>ClusterRoleBinding: system:auth-delegator<br>Validates Pod JWT tokens with K8s API", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=11;", 110, 290, 320, 80)
    add_node(r6, "k_script_auth", "1", "<b>vault-k8s-auth-setup.ps1</b><br>Configures Kubernetes Auth Method<br>+ Least-Privilege Roles & Policies", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=11;", 110, 400, 320, 80)

    add_node(r6, "ns_istio", "1", "<b>🌐 NAMESPACE: istio-system</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 500, 120, 380, 480)
    add_node(r6, "k_istiod", "1", "<b>Deployment: istiod</b><br>Istio Control Plane & Citadel<br>Manages mTLS & Envoy proxy configs", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=12;", 530, 180, 320, 80)
    add_node(r6, "k_cacerts", "1", "<b>Secret: cacerts</b><br>Intermediate CA from Vault PKI<br>ca-cert.pem / root-cert.pem", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=1.5;fontColor=#312E81;fontSize=11;", 530, 290, 320, 80)
    add_node(r6, "k_ingw", "1", "<b>Deployment: istio-ingressgateway</b><br>Edge Proxy LoadBalancer (Port 80/443)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=1.5;fontColor=#312E81;fontSize=11;", 530, 400, 320, 80)

    add_node(r6, "ns_default", "1", "<b>📦 NAMESPACE: ecommerce (Apps & Databases)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 920, 120, 520, 480)
    add_node(r6, "k_sa_apps", "1", "<b>ServiceAccounts:</b><br>products-service • orders-service<br>inventory-service • notification-service • api-gateway", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 950, 180, 460, 70)
    add_node(r6, "k_eso_objs", "1", "<b>External Secrets Operator (ESO):</b><br>SecretStore: vault-secret-store<br>ExternalSecret -> Secret: microservices-secrets", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 950, 280, 460, 80)
    add_node(r6, "k_apps_pods", "1", "<b>Deployments & Pods (Istio Sidecar Injected):</b><br>api-gateway • products-service • orders-service<br>inventory-service • notification-service • frontend<br>Postgres (products, orders, inventory, keycloak) • Kafka • Redis", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 950, 390, 460, 90)

    # =========================================================================
    # PAGE 7: End-to-End Request Flow & Order Processing Sequence
    # =========================================================================
    r7 = create_page("page_e2e_sequence", "7. End-to-End Request Flow & Order Processing Sequence")
    add_node(r7, "t7", "1", "<b style='font-size:22px;color:#1E293B;'>END-TO-END REQUEST FLOW & ORDER PROCESSING SEQUENCE</b><br><span style='font-size:13px;color:#64748B;'>Complete journey: Angular 21 SPA ➔ Istio Ingress ➔ API Gateway ➔ Microservices ➔ Kafka ➔ Observability</span>", title_style, 300, 30, 1300, 50)

    # Sequence Actors
    add_node(r7, "e_fe", "1", "<b>1. Frontend SPA<br>(Angular 21)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 80, 110, 160, 50)
    add_node(r7, "e_igw", "1", "<b>2. Istio Ingress<br>Gateway (80/443)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 280, 110, 160, 50)
    add_node(r7, "e_kc", "1", "<b>3. Keycloak IAM<br>(OAuth2 / PKCE)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 480, 110, 160, 50)
    add_node(r7, "e_gw", "1", "<b>4. API Gateway<br>(Spring Cloud)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 680, 110, 160, 50)
    add_node(r7, "e_redis", "1", "<b>5. Redis 8.8<br>(Rate Limiter)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;strokeWidth=2;fontColor=#7F1D1D;fontSize=11;", 880, 110, 160, 50)
    add_node(r7, "e_ord", "1", "<b>6. Orders Service<br>(Spring Boot 3.4)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1080, 110, 160, 50)
    add_node(r7, "e_prod_inv", "1", "<b>7. Products &<br>Inventory (DBs)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1280, 110, 160, 50)
    add_node(r7, "e_kafka", "1", "<b>8. Kafka &<br>Notification</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 1480, 110, 160, 50)
    add_node(r7, "e_obs", "1", "<b>9. LGTM Telemetry<br>(OTel/Tempo/Loki)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=11;", 1680, 110, 160, 50)

    # Lifelines
    add_node(r7, "l_fe", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 160, 160, 10, 780)
    add_node(r7, "l_igw", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 360, 160, 10, 780)
    add_node(r7, "l_kc", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 560, 160, 10, 780)
    add_node(r7, "l_gw", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 760, 160, 10, 780)
    add_node(r7, "l_redis", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 960, 160, 10, 780)
    add_node(r7, "l_ord", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1160, 160, 10, 780)
    add_node(r7, "l_prod_inv", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1360, 160, 10, 780)
    add_node(r7, "l_kafka", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1560, 160, 10, 780)
    add_node(r7, "l_obs", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1760, 160, 10, 780)

    # Steps
    add_node(r7, "st1", "1", "1. User initiates Self-Registration or Login in Angular 21 SPA", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;fontSize=10;align=left;spacingLeft=8;", 160, 190, 400, 32)
    add_node(r7, "st2", "1", "2. Keycloak registers user, assigns default ROLE_USER, and issues signed JWT Access Token", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;fontSize=10;align=left;spacingLeft=8;", 160, 240, 400, 32)
    add_node(r7, "st3", "1", "3. HTTP POST /api/order (Authorization: Bearer &lt;JWT&gt;, traceparent)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;fontSize=10;align=left;spacingLeft=8;", 160, 290, 200, 32)
    add_node(r7, "st4", "1", "4. Istio Ingress Gateway terminates edge TLS & forwards via STRICT mTLS (SPIFFE ID)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;fontSize=10;align=left;spacingLeft=8;", 360, 340, 400, 32)
    add_node(r7, "st5", "1", "5. API Gateway evaluates Redis Token Bucket Rate Limiter (20 req/s, burst 40)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;fontSize=10;align=left;spacingLeft=8;", 760, 390, 200, 32)
    add_node(r7, "st6", "1", "6. API Gateway verifies JWT cryptographic signature against Keycloak JWKS endpoint", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;fontSize=10;align=left;spacingLeft=8;", 560, 440, 200, 32)
    add_node(r7, "st7", "1", "7. API Gateway creates OTel span and proxies request to Orders Service over mTLS", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 760, 490, 400, 32)
    add_node(r7, "st8", "1", "8. Orders Service calls Products Service (GET /api/product/{id}) to validate catalog & price", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 1160, 540, 200, 32)
    add_node(r7, "st9", "1", "9. Orders Service calls Inventory Service (POST /api/inventory/check-and-lock) to lock stock in db-inventory", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 1160, 590, 200, 32)
    add_node(r7, "st10", "1", "10. Orders Service binds authenticated userId/username and persists Order in db-orders (Multi-Tenant Isolation)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 1160, 640, 450, 32)
    add_node(r7, "st11", "1", "11. Orders Service emits 'orders-topic' event to Apache Kafka cluster (Port 9094 / SASL PLAIN)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;fontSize=10;align=left;spacingLeft=8;", 1160, 690, 400, 32)
    add_node(r7, "st12", "1", "12. Orders Service returns HTTP 201 Created response ➔ API Gateway ➔ Frontend SPA", "rounded=1;whiteSpace=wrap;html=1;fillColor=#DCFCE7;strokeColor=#16A34A;fontSize=10;align=left;spacingLeft=8;", 160, 740, 1000, 32)
    add_node(r7, "st13", "1", "13. Notification Service asynchronously consumes Kafka event over SASL PLAIN (Port 9094) & sends confirmation email", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;fontSize=10;align=left;spacingLeft=8;", 1560, 790, 150, 32)
    add_node(r7, "st14", "1", "14. Continuous Observability: Prometheus tracks conversion funnels, loyalty cohorts, basket sizes, logistics pipelines, idempotency & Grafana visualizes e-commerce business KPIs", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;fontSize=10;align=left;spacingLeft=8;dashed=1;", 760, 840, 1000, 32)

    # =========================================================================
    # PAGE 8: Mature E-Commerce Observability & Business Intelligence Architecture
    # =========================================================================
    r8 = create_page("page_ecommerce_obs", "8. Mature E-Commerce Observability Architecture")
    add_node(r8, "t8", "1", "<b style='font-size:22px;color:#1E293B;'>MATURE E-COMMERCE OBSERVABILITY & BUSINESS INTELLIGENCE (5 DIMENSIONS)</b><br><span style='font-size:13px;color:#64748B;'>High-cardinality prevention (O(1) discrete cohorts), conversion funnel, 5-stage logistics state machine, and distributed saga resilience</span>", title_style, 300, 30, 1400, 50)

    # Dimension 1
    add_node(r8, "d1", "1", "<b>1. Financial & Executive KPIs</b><br>• Net Completed Orders & Revenue ($ USD)<br>• Average Order Value (AOV)<br>• Collected Taxes (IVA/Tax)<br>• Shipping Revenue (DHL Express)<br>• Total Units Sold", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;align=left;spacingLeft=15;", 100, 120, 320, 160)

    # Dimension 2
    add_node(r8, "d2", "1", "<b>2. Conversion Funnel & Cart</b><br>• Cart Additions (<code>ecommerce_cart_additions_total</code>)<br>• Checkout Started (<code>ecommerce_checkout_started_total</code>)<br>• Payment Step (<code>ecommerce_checkout_step_reached_total</code>)<br>• Cart Abandonment Rate (%)<br>• Payment Brand & Delivery Market Share", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;align=left;spacingLeft=15;", 460, 120, 340, 160)

    # Dimension 3
    add_node(r8, "d3", "1", "<b>3. Inventory Intelligence</b><br>• Live Available Stock by SKU<br>• SKU Sales Market Share<br>• Stockout Incidents (<code>inventory_out_of_stock_events_total</code>)<br>• Low Stock Warnings (&lt;5 units)<br>• Warehouse Restock Operations", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;align=left;spacingLeft=15;", 840, 120, 320, 160)

    # Dimension 4
    add_node(r8, "d4", "1", "<b>4. 5-Stage Logistics Pipeline</b><br>• <code>PLACED</code>: Order created & inventory reserved<br>• <code>PAYMENT_CONFIRMED</code>: Capture verified<br>• <code>PREPARING</code>: Warehouse picking & packing<br>• <code>SHIPPED</code>: In transit with DHL tracking<br>• <code>DELIVERED</code>: Final mile receipt confirmed", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;align=left;spacingLeft=15;", 1200, 120, 320, 160)

    # Dimension 5
    add_node(r8, "d5", "1", "<b>5. Distributed Consistency & Resilience</b><br>• Duplicate Orders Prevented (Idempotency Hits)<br>• Saga Distributed Rollbacks & Compensations<br>• Notification Kafka Processing Throughput & Lag<br>• Resilience4j Circuit Breaker Health Matrix", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;align=left;spacingLeft=15;", 100, 320, 320, 160)

    # Customer Retention Architecture (O(1) Cardinality)
    add_node(r8, "ret_box", "1", "<b>CUSTOMER RETENTION & BASKET DYNAMICS (O(1) Bounded Cardinality Architecture)</b><br>• <b>Problem:</b> Tagging metrics with unbounded <code>username</code> causes cardinality explosion (millions of time series in Prometheus TSDB).<br>• <b>Solution:</b> Aggregation into discrete business cohorts: <code>first_time</code>, <code>repeat</code>, and <code>loyal_vip</code>.<br>• <b>Basket Economics:</b> Order volume segmentation by basket size: <code>single_item</code>, <code>2_3_items</code>, <code>bulk_4_plus</code>.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 460, 320, 1060, 160)

    # Dashboard Mapping
    add_node(r8, "dash_biz", "1", "<b>📊 Grafana Dashboard: Curated Business Operations (10 High-Value Panels)</b><br>• <b>Dynamic Filter:</b> <code>Filter Microservice</code> dropdown (All / Orders / Inventory / Products)<br>• <b>1. Executive Summary:</b> Net Revenue, Net Orders, AOV & Abandonment Rate (Safe Clamping)<br>• <b>2. Conversion & Logistics:</b> Funnel Stages & 5-Stage Logistics Pipeline<br>• <b>3. Inventory & Demand:</b> Live Stock by SKU (Alerts &lt;5) & Top Selling SKUs Share<br>• <b>4. Customer Retention:</b> Discrete Loyalty Cohorts (O(1)) & Growth Timeline", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;align=left;spacingLeft=20;", 100, 520, 700, 200)

    add_node(r8, "dash_tech", "1", "<b>🛡️ Grafana Dashboard: Curated Technical & SRE Operations (12 Essential Panels)</b><br>• <b>Dynamic Filter:</b> <code>Filter Microservice</code> drilldown (All / Gateway / Orders / Inventory / Products / Notif)<br>• <b>1. Global Health:</b> Core Microservices Online (5 Roles, Replica-Invariant), Global P95, Threat Level, Circuit Breakers<br>• <b>2. HTTP Golden Signals:</b> Request Rate (RPS: 2xx/4xx/5xx) & P95 Latency per Service<br>• <b>3. Distributed Resilience:</b> Idempotency Hits, Saga Rollbacks & Kafka Streaming Rate<br>• <b>4. Platform Saturation:</b> JVM Heap Memory, CPU & HikariCP Database Connection Pools (Active vs Total Pool Size)<br>• <b>5. Security & Diagnostics:</b> Blocked Attacks (HTTP 429) & Incident Logs Stream (Loki)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=12;align=left;spacingLeft=20;", 840, 520, 680, 200)

    # =========================================================================
    # PAGE 9: 100% Local Enterprise DevSecOps Platform & 12-Stage Pipeline
    # =========================================================================
    r9 = create_page("page_devsecops_pipeline", "9. Enterprise DevSecOps Platform & 12-Stage Pipeline")
    add_node(r9, "t9", "1", "<b style='font-size:22px;color:#1E293B;'>100% LOCAL ENTERPRISE DEVSECOPS PLATFORM & 12-STAGE CI/CD PIPELINE</b><br><span style='font-size:13px;color:#64748B;'>Hardware Budget: AMD Ryzen 7 (16 threads) • 32 GB RAM • Minikube (12 CPUs / 12 GB RAM) • Zero Cloud Cost Production Parity</span>", title_style, 300, 25, 1400, 50)

    # Section 1: CI Phase Flow
    add_node(r9, "c_ci", "1", "<b>🔨 CI PHASE: Continuous Integration & Shift-Left Security (GitHub Actions Windows Runner)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 60, 90, 750, 190)
    add_node(r9, "s1", "1", "<b>1. Unit Tests</b><br>Maven / Angular<br>JaCoCo Coverage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=10;", 80, 130, 125, 65)
    add_node(r9, "s2", "1", "<b>2. SAST & Secrets</b><br>SonarQube Scan<br>Gitleaks Audit", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=10;", 225, 130, 125, 65)
    add_node(r9, "s3", "1", "<b>3. Container Build</b><br>Docker Daemon<br>Syft SBOM Gen", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=10;", 370, 130, 125, 65)
    add_node(r9, "s4", "1", "<b>4. Trivy Scan</b><br>Container Audit<br>.trivyignore allow", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=10;", 515, 130, 125, 65)
    add_node(r9, "s5", "1", "<b>5. Conftest (OPA)</b><br>Helm Pre-flight<br>Rego Policy Audit", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=10;", 660, 130, 135, 65)

    add_edge(r9, "pe1", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "s1", "s2")
    add_edge(r9, "pe2", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "s2", "s3")
    add_edge(r9, "pe3", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "s3", "s4")
    add_edge(r9, "pe4", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "s4", "s5")

    # Section 2: CD Staging, Promotion & Prod
    add_node(r9, "c_cd", "1", "<b>🚀 CD PHASE: Staging Quality Gates, Docker Hub Promotion & Production Canary</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 830, 90, 1010, 190)
    add_node(r9, "s6", "1", "<b>6. Deploy Staging</b><br>Helm Umbrella<br>SPRING=staging", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=10;", 850, 130, 125, 65)
    add_node(r9, "s7", "1", "<b>7. Newman QA</b><br>API Integration<br>Postman Tests", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=1.5;fontColor=#4C1D95;fontSize=10;", 990, 130, 120, 65)
    add_node(r9, "s8", "1", "<b>8. Cypress E2E</b><br>UI Journey<br>Checkout Test", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=1.5;fontColor=#4C1D95;fontSize=10;", 1125, 130, 120, 65)
    add_node(r9, "s9", "1", "<b>9. k6 Load Tests</b><br>SLO: p95&lt;500ms<br>Error Rate &lt; 1%", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=1.5;fontColor=#4C1D95;fontSize=10;", 1260, 130, 125, 65)
    add_node(r9, "s10", "1", "<b>10. OWASP ZAP</b><br>DAST Ingress Scan<br>Edge Attack Audit", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;strokeWidth=1.5;fontColor=#7F1D1D;fontSize=10;", 1400, 130, 125, 65)
    add_node(r9, "s11", "1", "<b>11. Push Docker Hub</b><br>georgegxx/*:1.0.0<br>Certified Release", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=10;", 1540, 130, 135, 65)
    add_node(r9, "s12", "1", "<b>12. Deploy Prod</b><br>Canary Rollout<br>Istio 10% ➔ 100%", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=10;", 1690, 130, 135, 65)

    add_edge(r9, "pe5", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=2;", "s5", "s6")
    add_edge(r9, "pe6", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "s6", "s7")
    add_edge(r9, "pe7", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "s7", "s8")
    add_edge(r9, "pe8", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "s8", "s9")
    add_edge(r9, "pe9", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#EF4444;strokeWidth=1.5;", "s9", "s10")
    add_edge(r9, "pe10", "1", "", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=2;", "s10", "s11")
    add_edge(r9, "pe11", "1", "Quality Gates Passed", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#F59E0B;strokeWidth=2;", "s11", "s12")

    # Section 3: Minikube In-Cluster Platform & Live Endpoints
    add_node(r9, "c_plat", "1", "<b>☸️ MINIKUBE PLATFORM TOPOLOGY (12 CPUs • 12 GB RAM • containerd • Ingress Controller)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 310, 1780, 380)

    # Tool Pods
    add_node(r9, "p_loki", "1", "<b>📑 Loki & Alloy Logs</b><br>observability namespace<br>Log Aggregation Engine<br>Grafana Logs Datasource", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 90, 360, 240, 90)
    add_node(r9, "p_argo", "1", "<b>🐙 ArgoCD GitOps</b><br>Port 8088 (Web UI)<br>GitOps Controller (admin/admin)<br>Automated Sync Engine", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 360, 360, 240, 90)
    add_node(r9, "p_vault", "1", "<b>🔒 HashiCorp Vault</b><br>Port 8200 (Token: root)<br>Secrets Management<br>K8s ServiceAccount Auth", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 630, 360, 240, 90)
    add_node(r9, "p_gatekeeper", "1", "<b>🛡️ OPA Gatekeeper</b><br>Admission Controller<br>Trusted Registry (georgegxx/*)<br>Resource Limits Guardrail", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 900, 360, 240, 90)
    add_node(r9, "p_grafana", "1", "<b>📊 Grafana Observability</b><br>Port 3000 (admin/admin)<br>Technical & Business Dashboards<br>Prometheus + Loki Integrations", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 1170, 360, 240, 90)
    add_node(r9, "p_prom", "1", "<b>📈 Prometheus Targets</b><br>Port 9090 (TSDB /targets)<br>15s Scrape Interval<br>Actuator Metrics Ingestion", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1440, 360, 240, 90)

    # Applications Layer in Staging
    add_node(r9, "app_ang", "1", "<b>🌐 Frontend Angular 21</b><br>Port 4200 (Storefront SPA)<br>Dynamic Product Catalog<br>Responsive UI", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 90, 480, 240, 90)
    add_node(r9, "app_gw", "1", "<b>🔌 Spring Cloud Gateway</b><br>Port 8080 (/api/product)<br>Swagger: /swagger-ui.html<br>Keycloak JWT & Rate Limit", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 360, 480, 240, 90)
    add_node(r9, "app_kc", "1", "<b>🔑 Keycloak 26 IAM</b><br>Port 8181 (admin/admin)<br>Realm: microservices-realm<br>OIDC & User Management", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 630, 480, 240, 90)
    add_node(r9, "app_istio", "1", "<b>🚪 Istio Unified Edge</b><br>Port 30080 (Ingress Gateway)<br>Routes: /, /api/*, /admin/*<br>Zero-Trust Service Mesh", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 900, 480, 240, 90)
    add_node(r9, "app_kiali", "1", "<b>🧭 Kiali Visual Mesh</b><br>Port 20001 (/kiali)<br>Real-time Traffic Graph<br>mTLS Encryption Health", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 1170, 480, 240, 90)
    add_node(r9, "app_dbs", "1", "<b>💾 Persistence & Streams</b><br>PostgreSQL (Products, Orders, Inv, KC)<br>Apache Kafka 7.8 (Port 9094 SASL PLAIN)<br>Redis Cache Cluster", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=11;", 1440, 480, 240, 90)

    # Section 4: Architecture Operational Summary
    add_node(r9, "ops_box", "1", "<b>⚙️ AUTOMATED LIFECYCLE SCRIPTS (Platform Engineering)</b><br>• <b>Bootstrap Ecosystem:</b> <code>.\\scripts\\devsecops\\bootstrap-local-devsecops.ps1</code> (Deploys Minikube, Terraform, ArgoCD, Prometheus, Gatekeeper, Vault, Keycloak, Frontend & Tunnels).<br>• <b>Health Verification:</b> <code>.\\scripts\\devsecops\\verify-platform.ps1</code> (Runs automated deep diagnostics of all namespaces, pods, NodePorts, and policies).<br>• <b>Teardown & Pause:</b> <code>.\\scripts\\devsecops\\teardown-local-devsecops.ps1</code> (Gracefully pauses Minikube and frees 12 CPUs & 12 GB RAM, preserving state).<br>• <b>Total Cluster Purge:</b> <code>.\\scripts\\devsecops\\teardown-local-devsecops.ps1 -DeleteCluster -CleanTerraformState</code> (Destroys all volumes and reclaims 80 GB disk).", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 60, 590, 1780, 85)

    tree = ET.ElementTree(root_mxfile)
    ET.indent(tree, space="  ", level=0)
    tree.write("docs/Diagrams.drawio", encoding="utf-8", xml_declaration=True)
    print("Successfully generated docs/Diagrams.drawio in English with 9 comprehensive tabs!")

if __name__ == "__main__":
    build_drawio_xml()

