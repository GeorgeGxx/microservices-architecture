import xml.etree.ElementTree as ET

def build_drawio_xml():
    root_mxfile = ET.Element("mxfile", host="Electron", pages="12", type="device")

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
    add_node(r1, "t1", "1", "<b style='font-size:22px;color:#1E293B;'>ECOMMERCE - MICROSERVICES ARCHITECTURE OVERVIEW</b><br><span style='font-size:13px;color:#64748B;'>Spring Boot 4.0.8 • React 19 • TailwindCSS v4 • Keycloak 26 • Kafka KRaft • Istio Mesh • HashiCorp Vault • Full-Stack Observability</span>", title_style, 300, 30, 1200, 50)

    # Client Layer
    add_node(r1, "c_client", "1", "<b>🌐 CLIENT LAYER</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 110, 340, 420)
    add_node(r1, "n_spa", "1", "<b>React 19 SPA Storefront</b><br>Nginx Gateway (Port 4200)<br>Unified Global Search • User Wishlist<br>Keycloak RBAC (Admin/User) • Real-Time SSE", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 170, 280, 70)
    add_node(r1, "n_traffic", "1", "<b>Traffic Simulator</b><br>simulate.py (traffic)<br>Load & E2E Purchase Flow", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 270, 280, 70)
    add_node(r1, "n_postman", "1", "<b>Postman / Newman Suite</b><br>GraphQL Federation 2.3<br>Apollo Sandbox & Keycloak OIDC", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=12;", 90, 370, 280, 70)

    # Edge / Gateway & Security
    add_node(r1, "c_edge", "1", "<b>🛡️ EDGE & IDENTITY LAYER</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 440, 110, 380, 420)
    add_node(r1, "n_gw", "1", "<b>Apollo Router v2 (Gateway)</b><br>Port 8080 (Rust Engine)<br>Federation 2.3 Supergraph<br>Apollo Sandbox • OTLP Traces", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=12;", 470, 170, 320, 80)
    add_node(r1, "n_kc", "1", "<b>Keycloak 26 (IAM)</b><br>Port 8181 (OIDC / OAuth2)<br>Realm: microservices-realm<br>Self-Registration • Default USER Role<br>Users / Roles / PKCE", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=12;", 470, 280, 320, 80)
    add_node(r1, "n_db_kc", "1", "<b>PostgreSQL Keycloak</b><br>db-keycloak (Port 5434)<br>Persistent Realm Database", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=1.5;fontColor=#831843;fontSize=11;", 550, 400, 160, 70)

    # Microservices Backend Layer
    add_node(r1, "c_ms", "1", "<b>📦 CORE MICROSERVICES LAYER (Spring Boot 4.0.8 / Java 21)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 860, 110, 520, 780)
    add_node(r1, "n_prod", "1", "<b>Products Service</b><br>Port 8004<br>Catalog Management • Redis Cache", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 170, 220, 80)
    add_node(r1, "n_orders", "1", "<b>Orders Service</b><br>Port 8003<br>Saga Coordinator • Resilience4j<br>Multi-Tenant User Isolation (JWT sub)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 350, 220, 80)
    add_node(r1, "n_inv", "1", "<b>Inventory Service</b><br>Port 8001<br>Stock Validation • Lock/Deduct", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 530, 220, 80)
    add_node(r1, "n_notif", "1", "<b>Notification Service</b><br>Port 8002<br>Email Dispatcher • Event Consumer", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=12;", 900, 710, 220, 80)

    # Persistence Layer
    add_node(r1, "n_db_prod", "1", "<b>db-products</b><br>PostgreSQL 18<br>Port 5433", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 175, 160, 70)
    add_node(r1, "n_db_orders", "1", "<b>db-orders</b><br>PostgreSQL 18<br>Port 5432", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 355, 160, 70)
    add_node(r1, "n_db_inv", "1", "<b>db-inventory</b><br>PostgreSQL 18<br>Port 5431", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;", 1180, 535, 160, 70)

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
    add_edge(r1, "e1", "1", "GraphQL / OIDC", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#3B82F6;strokeWidth=2;", "n_spa", "n_gw")
    add_edge(r1, "e2", "1", "JWKS Validation", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#EC4899;strokeWidth=2;", "n_gw", "n_kc")
    add_edge(r1, "e3", "1", "Subgraph Query (_entities)", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#6366F1;strokeWidth=2;", "n_gw", "n_prod")
    add_edge(r1, "e4", "1", "Subgraph Query (_entities)", "edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#6366F1;strokeWidth=2;", "n_gw", "n_orders")
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
    add_node(r2, "e_kv", "1", "<b>KV-v2 Secrets Engine</b><br>secret/application<br>secret/products-service<br>secret/orders-service<br>secret/inventory-service<br>secret/notification-service<br>secret/apollo-router", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=11;align=left;spacingLeft=10;", 100, 320, 240, 140)
    add_node(r2, "e_db", "1", "<b>Dynamic Database Engine</b><br>database/config/postgres-products<br>database/roles/products-db-role<br>• On-the-fly user creation<br>• Automatic 1h TTL<br>• Auto-drop on expiration", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;align=left;spacingLeft=10;", 380, 320, 280, 140)
    add_node(r2, "e_tr", "1", "<b>Transit Encryption Engine</b><br>transit/keys/microservices-data-key<br>• Encryption as a Service<br>• AES256-GCM96<br>• Protects Credit Cards & PII<br>• Zero app key storage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=11;align=left;spacingLeft=10;", 700, 320, 280, 140)
    add_node(r2, "e_pki", "1", "<b>PKI Certificate Engine</b><br>pki_int (Intermediate CA)<br>• Emits ca-cert.pem / root-cert.pem<br>• Signs istio-system/cacerts<br>• Zero-Trust mTLS Mesh Trust", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FCE7F3;strokeColor=#DB2777;strokeWidth=1.5;fontColor=#831843;fontSize=11;align=left;spacingLeft=10;", 1020, 320, 280, 140)

    # 4 Integration Approaches
    add_node(r2, "app_compose", "1", "<b>Approach A: Docker Compose</b><br>Default fast startup via .env<br>Zero friction, fallback guaranteed", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 100, 520, 280, 90)
    add_node(r2, "app_spring", "1", "<b>Approach B: Native Spring Boot</b><br>--spring.profiles.active=vault<br>application-vault.yml in all 5 apps<br>Spring Cloud Vault direct connection", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 420, 520, 300, 90)
    add_node(r2, "app_eso", "1", "<b>Approach C: External Secrets (ESO)</b><br>K8s SecretStore & ExternalSecret<br>Syncs to microservices-secrets<br>Zero sidecar RAM footprint (Recommended)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 760, 520, 320, 90)
    add_node(r2, "app_sidecar", "1", "<b>Approach D: Vault Agent Sidecar</b><br>vault.hashicorp.com/agent-inject<br>Injects /vault/secrets/database.env<br>Multi-Cloud production standard", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#94A3B8;strokeWidth=2;fontColor=#334155;fontSize=12;", 1120, 520, 300, 90)

    # Least Privilege Policies
    add_node(r2, "pol_box", "1", "<b>LEAST-PRIVILEGE ACCESS POLICIES (Service-Level Isolation)</b><br>• <b>products-service-policy:</b> READ secret/data/products-service + secret/data/application<br>• <b>orders-service-policy:</b> READ secret/data/orders-service + secret/data/application<br>• <b>inventory-service-policy:</b> READ secret/data/inventory-service + secret/data/application<br>• <b>notification-service-policy:</b> READ secret/data/notification-service + secret/data/application<br>• <b>apollo-router-policy:</b> READ secret/data/apollo-router + secret/data/application", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=1.5;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 100, 660, 1320, 120)

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

    add_node(r4, "pod_gw", "1", "<b>Pod: apollo-router</b><br>Rust Router (8080)<br>+ Envoy Sidecar Proxy<br><span style='color:#059669;'>spiffe://cluster.local/ns/ecommerce/sa/apollo-router</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 140, 350, 320, 90)
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
    add_node(r6, "t6", "1", "<b style='font-size:22px;color:#1E293B;'>KUBERNETES & MINIKUBE CLUSTER TOPOLOGY</b><br><span style='font-size:13px;color:#64748B;'>Pure Separation of Concerns (SoC): staging, auth, data, observability, vault, and istio-system</span>", title_style, 300, 30, 1200, 50)

    # Namespaces
    add_node(r6, "ns_vault", "1", "<b>🔒 NAMESPACE: vault</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 110, 280, 420)
    add_node(r6, "k_vault_pod", "1", "<b>Deployment: vault</b><br>hashicorp/vault:2.0.4<br>Port 8200", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=2;fontColor=#581C87;fontSize=11;", 80, 160, 240, 70)
    add_node(r6, "k_sa_vault", "1", "<b>ServiceAccount: vault-auth</b><br>ClusterRoleBinding: system:auth-delegator", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=10;", 80, 250, 240, 70)
    add_node(r6, "k_script_auth", "1", "<b>vault-k8s-auth-setup.ps1</b><br>Kubernetes Auth Method & App Roles", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#A855F7;strokeWidth=1.5;fontColor=#581C87;fontSize=10;", 80, 340, 240, 70)

    add_node(r6, "ns_auth", "1", "<b>🛡️ NAMESPACE: auth</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 360, 110, 300, 420)
    add_node(r6, "k_kc_pod", "1", "<b>Deployment: keycloak</b><br>Keycloak 26.7.3 (IdP)<br>Port 8181 (HTTP) & 9000 (Metrics)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 380, 160, 260, 70)
    add_node(r6, "k_db_kc", "1", "<b>StatefulSet: db-keycloak</b><br>PostgreSQL 18 (Port 5432)<br>Dedicated IAM database", "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=10;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=1.5;fontColor=#831843;fontSize=10;", 380, 250, 260, 70)

    add_node(r6, "ns_data", "1", "<b>💾 NAMESPACE: data (Stateful & Exporters)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 680, 110, 380, 420)
    add_node(r6, "k_data_pods", "1", "<b>StatefulSets:</b><br>• Kafka KRaft (9092/9094)<br>• Redis 8.8 (6379)<br>• Postgres (orders, inventory, products: 5432)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 700, 160, 340, 90)
    add_node(r6, "k_data_exp", "1", "<b>Infrastructure Exporters:</b><br>• kafka-exporter v1.9.0 (Port 9308)<br>• postgres-exporter v0.20.1 (Port 9187)<br>• redis-exporter (Port 9121)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=10;", 700, 270, 340, 90)

    add_node(r6, "ns_staging", "1", "<b>📦 NAMESPACE: staging (Core Microservices)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 1080, 110, 400, 420)
    add_node(r6, "k_apps_pods", "1", "<b>Deployments (Istio Sidecars Injected):</b><br>• apollo-router (8080)<br>• products-service (8004)<br>• orders-service (8003)<br>• inventory-service (8001)<br>• notification-service (8002)<br>• frontend React 19 SPA (80)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1100, 160, 360, 120)
    add_node(r6, "k_eso_objs", "1", "<b>ExternalName Cross-Namespace Bridges:</b><br>• keycloak -> keycloak.auth<br>• kafka / redis / db-* -> data.svc", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=10;", 1100, 300, 360, 80)

    add_node(r6, "ns_obs", "1", "<b>📊 NAMESPACE: observability (LGTM Telemetry)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 1500, 110, 360, 420)
    add_node(r6, "k_obs_pods", "1", "<b>Observability Stack:</b><br>• Prometheus v3.14 (Port 9090)<br>• Grafana 13.2 (Port 3000)<br>• Tempo 3.0 (Port 3200)<br>• Loki 3.7 (Port 3100)<br>• Alloy v1.18 (DaemonSet)<br>• OTel Collector (4317/4318)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 1520, 160, 320, 160)

    # Namespace KEDA
    add_node(r6, "ns_keda", "1", "<b>⚖️ NAMESPACE: keda (Event-Driven Autoscaling)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 560, 580, 200)
    add_node(r6, "k_keda_op", "1", "<b>Deployment: keda-operator (v2.20.1)</b><br>CRD Controller: ScaledObject & TriggerAuthentication<br>Event-Driven Scaler (Kafka Lag, Prometheus RPS, Redis)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 80, 610, 540, 60)
    add_node(r6, "k_keda_ms", "1", "<b>Deployment: keda-metrics-apiserver (v2.20.1)</b><br>External Metrics API Provider for Kubernetes HPA (autoscaling/v2)<br>Translates external telemetry to native HPA metrics", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 80, 685, 540, 60)

    # =========================================================================
    # PAGE 7: End-to-End Request Flow & Order Processing Sequence
    # =========================================================================
    r7 = create_page("page_e2e_sequence", "7. End-to-End Request Flow & Order Processing Sequence")
    add_node(r7, "t7", "1", "<b style='font-size:22px;color:#1E293B;'>END-TO-END REQUEST FLOW & ORDER PROCESSING SEQUENCE</b><br><span style='font-size:13px;color:#64748B;'>Complete journey: React 19 SPA ➔ Istio Ingress ➔ Apollo Router v2 ➔ Federated Subgraphs ➔ Kafka ➔ Observability</span>", title_style, 300, 30, 1300, 50)

    # Sequence Actors
    add_node(r7, "e_fe", "1", "<b>1. Client / SPA<br>(React 19 + Tailwind)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 60, 110, 150, 50)
    add_node(r7, "e_igw", "1", "<b>2. Ingress Controller<br>(Istio)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 240, 110, 170, 50)
    add_node(r7, "e_kc", "1", "<b>3. Keycloak IAM<br>(OIDC / PKCE / JWKS)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 440, 110, 160, 50)
    add_node(r7, "e_mesh", "1", "<b>4. Istio Envoy Mesh<br>(mTLS STRICT SPIFFE)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 630, 110, 160, 50)
    add_node(r7, "e_gw", "1", "<b>5. Apollo Router v2<br>(Query Planner / Fed 2.3)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 820, 110, 170, 50)
    add_node(r7, "e_ord", "1", "<b>6. Orders Service<br>(Spring Boot 4.0.8)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1020, 110, 150, 50)
    add_node(r7, "e_prod_inv", "1", "<b>7. Products / Inventory<br>& Kafka KRaft</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 1200, 110, 170, 50)
    add_node(r7, "e_obs", "1", "<b>8. Kiali Dashboard &<br>LGTM Observability</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=11;", 1400, 110, 180, 50)

    # Lifelines
    add_node(r7, "l_fe", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 135, 160, 10, 780)
    add_node(r7, "l_igw", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 325, 160, 10, 780)
    add_node(r7, "l_kc", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 520, 160, 10, 780)
    add_node(r7, "l_mesh", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 710, 160, 10, 780)
    add_node(r7, "l_gw", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 905, 160, 10, 780)
    add_node(r7, "l_ord", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1095, 160, 10, 780)
    add_node(r7, "l_prod_inv", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1285, 160, 10, 780)
    add_node(r7, "l_obs", "1", "", "shape=line;strokeWidth=2;strokeColor=#CBD5E1;direction=south;", 1490, 160, 10, 780)

    # Steps
    add_node(r7, "st1", "1", "1. User initiates OAuth2 Login / PKCE flow from React 19 SPA (CartAggregate & Checkout FSM)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;fontSize=10;align=left;spacingLeft=8;", 135, 190, 420, 32)
    add_node(r7, "st2", "1", "2. Ingress Controller (Istio) routes auth requests directly to Keycloak", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;fontSize=10;align=left;spacingLeft=8;", 325, 235, 385, 32)
    add_node(r7, "st3", "1", "3. Keycloak validates credentials, issues signed JWT Access Token (JWKS, roles, 'sub')", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;fontSize=10;align=left;spacingLeft=8;", 135, 280, 385, 32)
    add_node(r7, "st4", "1", "4. GraphQL POST / (Authorization: Bearer &lt;JWT&gt;, X-Idempotency-Key, traceparent)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;fontSize=10;align=left;spacingLeft=8;", 135, 325, 385, 32)
    add_node(r7, "st5", "1", "5. Ingress Controller applies L7 security: rate-limiting (100 req/s), security headers & WAF sanitization", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;fontSize=10;align=left;spacingLeft=8;", 325, 370, 385, 32)
    add_node(r7, "st6", "1", "6. Istio Envoy Sidecar intercepts egress, applies VirtualService & encrypts with STRICT mTLS", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 710, 415, 195, 32)
    add_node(r7, "st7", "1", "7. Apollo Router v2 validates JWT against Keycloak JWKS & constructs federated query plan", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;fontSize=10;align=left;spacingLeft=8;", 520, 460, 385, 32)
    add_node(r7, "st8", "1", "8. Apollo Router dispatches concurrent subgraph queries to orders-service:8003 over mTLS", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 905, 505, 190, 32)
    add_node(r7, "st9", "1", "9. Orders Service verifies inventory with Inventory Service and creates saga transaction in PostgreSQL", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;fontSize=10;align=left;spacingLeft=8;", 1095, 550, 190, 32)
    add_node(r7, "st10", "1", "10. Orders Service publishes order-created event to Kafka KRaft (Port 9094 / SASL PLAIN)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;fontSize=10;align=left;spacingLeft=8;", 1095, 595, 190, 32)
    add_node(r7, "st11", "1", "11. Orders Service returns Order entity ➔ Apollo Router merges subgraphs ➔ Ingress ➔ React 19 SPA", "rounded=1;whiteSpace=wrap;html=1;fillColor=#DCFCE7;strokeColor=#16A34A;fontSize=10;align=left;spacingLeft=8;", 135, 640, 960, 32)
    add_node(r7, "st12", "1", "12. Kiali Dashboard captures mesh topology: [Ingress] ➔ [apollo-router] ➔ [orders-service] with green 🔒 mTLS lock", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;fontSize=10;align=left;spacingLeft=8;dashed=1;", 710, 690, 780, 32)
    add_node(r7, "st13", "1", "13. Full Telemetry Collection: Prometheus scrapes RPS/latencies, Tempo correlates OTel spans, Loki indexes logs", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;fontSize=10;align=left;spacingLeft=8;dashed=1;", 905, 740, 585, 32)

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

    add_node(r8, "dash_infra", "1", "<b>⚙️ Prometheus Infrastructure Targets: Full-Stack Coverage (All Targets UP)</b><br>• <b>redis-exporter:</b> Cache hit ratio, keyspace stats, memory limit, rate limiter load (Port 9121)<br>• <b>kafka-exporter v1.9.0:</b> Consumer lag, topic partition throughput, broker count (Port 9308)<br>• <b>postgres-exporter v0.20.1:</b> Active connections, commit rate, lock deadlocks (Port 9187)<br>• <b>keycloak:</b> OIDC authentication success/fail, token issuance latency, JVM heap (Port 9000)<br>• <b>vault & istiod:</b> KMS seal status, API rates, Envoy mesh telemetry & mTLS golden signals", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=12;align=left;spacingLeft=20;", 100, 740, 1420, 100)

    # =========================================================================
    # PAGE 9: 100% Local Enterprise DevSecOps Platform & 12-Stage Pipeline
    # =========================================================================
    r9 = create_page("page_devsecops_pipeline", "9. Enterprise DevSecOps Platform & 12-Stage Pipeline")
    add_node(r9, "t9", "1", "<b style='font-size:22px;color:#1E293B;'>100% LOCAL ENTERPRISE DEVSECOPS PLATFORM & 12-STAGE CI/CD PIPELINE</b><br><span style='font-size:13px;color:#64748B;'>Hardware Budget: Intel/AMD (8+ cores) • 16+ GB RAM • Minikube (6 CPUs / 12 GB RAM / 40 GB disk) • Zero Cloud Cost Production Parity</span>", title_style, 300, 25, 1400, 50)

    # Section 1: CI Phase Flow
    add_node(r9, "c_ci", "1", "<b>🔨 CI PHASE: Continuous Integration & Shift-Left Security (GitHub Actions Windows Runner)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 60, 90, 750, 190)
    add_node(r9, "s1", "1", "<b>1. Unit Tests</b><br>Maven / React 19<br>JaCoCo Coverage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=10;", 80, 130, 125, 65)
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
    add_node(r9, "c_plat", "1", "<b>☸️ MINIKUBE PLATFORM TOPOLOGY (6 CPUs • 12 GB RAM • containerd • Ingress Controller)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=13;dashed=1;", 60, 310, 1780, 380)

    # Tool Pods
    add_node(r9, "p_loki", "1", "<b>📑 Loki & Alloy Logs</b><br>observability namespace<br>Log Aggregation Engine<br>Grafana Logs Datasource", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 90, 360, 240, 90)
    add_node(r9, "p_argo", "1", "<b>🐙 ArgoCD GitOps</b><br>Port 8088 (Web UI)<br>GitOps Controller (admin/admin)<br>Automated Sync Engine", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 360, 360, 240, 90)
    add_node(r9, "p_vault", "1", "<b>🔒 HashiCorp Vault</b><br>Port 8200 (Token: root)<br>Secrets Management<br>K8s ServiceAccount Auth", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 630, 360, 240, 90)
    add_node(r9, "p_gatekeeper", "1", "<b>🛡️ OPA Gatekeeper</b><br>Admission Controller<br>Trusted Registry (georgegxx/*)<br>Resource Limits Guardrail", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 900, 360, 240, 90)
    add_node(r9, "p_grafana", "1", "<b>📊 Grafana Observability</b><br>Port 3000 (admin/admin)<br>Technical & Business Dashboards<br>Prometheus + Loki Integrations", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 1170, 360, 240, 90)
    add_node(r9, "p_prom", "1", "<b>📈 Prometheus Targets</b><br>Port 9090 (TSDB /targets)<br>15s Scrape Interval<br>Actuator Metrics Ingestion", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1440, 360, 240, 90)

    # Applications Layer in Staging
    add_node(r9, "app_react", "1", "<b>🌐 Frontend React 19</b><br>Tailwind v4 (Port 4200)<br>Tactical DDD & Clean Arch<br>Compound UI & Checkout FSM", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 90, 480, 240, 90)
    add_node(r9, "app_gw", "1", "<b>🚀 Apollo Router v2</b><br>Port 8080 (/graphql)<br>Sandbox: http://localhost:8080<br>Apollo Federation 2.3 Supergraph", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EEF2FF;strokeColor=#6366F1;strokeWidth=2;fontColor=#312E81;fontSize=11;", 360, 480, 240, 90)
    add_node(r9, "app_kc", "1", "<b>🔑 Keycloak 26 IAM</b><br>Port 8181 (admin/admin)<br>Realm: microservices-realm<br>OIDC & User Management", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=2;fontColor=#831843;fontSize=11;", 630, 480, 240, 90)
    add_node(r9, "app_istio", "1", "<b>🚪 Istio Unified Edge</b><br>Port 30080 (Ingress Gateway)<br>Routes: /, /api/*, /admin/*<br>Zero-Trust Service Mesh", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 900, 480, 240, 90)
    add_node(r9, "app_kiali", "1", "<b>🧭 Kiali Visual Mesh</b><br>Port 20001 (/kiali)<br>Real-time Traffic Graph<br>mTLS Encryption Health", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 1170, 480, 240, 90)
    add_node(r9, "app_dbs", "1", "<b>💾 Persistence & Streams</b><br>PostgreSQL (Products, Orders, Inv, KC)<br>Apache Kafka 7.8 (Port 9094 SASL PLAIN)<br>Redis Cache Cluster", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=11;", 1440, 480, 240, 90)

    add_node(r9, "ops_box", "1", "<b>⚙️ UNIFIED PLATFORM CLI & OPERATIONAL LIFECYCLE</b><br>• <b>Unified Orchestrator:</b> <code>.\\platform.ps1 up</code> (Minikube, Istio, ArgoCD, Prometheus, Vault, Keycloak, Apps & Tunnels).<br>• <b>Health Doctor:</b> <code>.\\platform.ps1 doctor</code> (Deep diagnostics of pods, NodePorts, and active Gatekeeper OPA policies).<br>• <b>FinOps Cost Engine:</b> <code>.\\platform.ps1 cost -Environment minikube|staging|prod</code> (Air-gapped cost & savings breakdown).<br>• <b>Endpoints Table:</b> <code>.\\platform.ps1 urls</code> (Formatted table of active services and credentials).<br>• <b>Teardown & Purge:</b> <code>.\\platform.ps1 down [-DeleteCluster]</code> (Releases 6 CPUs & 12 GB RAM, or cleans 40 GB disk).", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 60, 590, 1780, 85)

    # =========================================================================
    # PAGE 10: Production Resiliency, External Secrets, Canary & Alerting
    # =========================================================================
    r10 = create_page("page_resiliency_canary_ops", "10. Resiliency, Secrets, Canary & Alerts")
    add_node(r10, "t10", "1", "<b style='font-size:22px;color:#1E293B;'>PRODUCTION-GRADE RESILIENCY, SECRETS, CANARY & ALERTING ARCHITECTURE</b><br><span style='font-size:13px;color:#64748B;'>KEDA v2.20.1 Event-driven Autoscaling • Horizontal Pod Autoscaler (HPA) • PodDisruptionBudgets (PDB) • External Secrets Operator + Vault • Istio Canary Mesh • Alertmanager Routing</span>", title_style, 300, 25, 1400, 50)

    # Section 1: HPA & PDB Quorum Protection
    add_node(r10, "c_hpa", "1", "<b>⚖️ AUTOSCALING & HIGH AVAILABILITY (KEDA v2.20.1 + HPA & PDB)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 60, 90, 420, 470)
    add_node(r10, "n_hpa", "1", "<b>KEDA v2.20.1 Event Autoscaler + HPA</b><br>• Kafka Consumer Lag: notification-service (lag &gt; 10)<br>• Prometheus RPS: apollo-router (req/s &gt; 100)<br>• CPU Target: 70% • Memory Target: 80%<br>• ScaledObjects unify event + resource triggers<br>• Auto-generates unified HPA with zero flapping", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 80, 140, 380, 90)
    add_node(r10, "n_pdb", "1", "<b>PodDisruptionBudgets (PDB)</b><br>• minAvailable: 1 across all 5 services<br>• Guarantees application quorum<br>• Zero downtime during node drains & updates<br>• Dynamic allowedDisruptions calculation", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 80, 245, 380, 75)
    add_node(r10, "n_pods", "1", "<b>Protected Microservice Deployments</b><br>• apollo-router (Port 8080)<br>• inventory-service (Port 8001)<br>• notification-service (Port 8002)<br>• orders-service (Port 8003)<br>• products-service (Port 8004)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 80, 335, 380, 100)
    add_node(r10, "n_mem_opt", "1", "<b>💡 Event-Driven Scaling Guarantee</b><br>KEDA controls HPA via ScaledObjects.<br>No duplicate HPAs, no replica race conditions.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=10;", 80, 450, 380, 60)

    add_edge(r10, "e_hpa_pod", "1", "Scale Controller", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "n_hpa", "n_pods")
    add_edge(r10, "e_pdb_pod", "1", "Quorum Guard", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_pdb", "n_pods")

    # Section 2: Vault + External Secrets Operator (ESO)
    add_node(r10, "c_eso", "1", "<b>🔐 SECRETS MANAGEMENT (ESO + VAULT)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 510, 90, 420, 470)
    add_node(r10, "n_vault_dev", "1", "<b>HashiCorp Vault (Port 8200)</b><br>• KV-v2 Secrets Engine at 'secret/'<br>• secret/data/application (DB & JWT)<br>• secret/data/apollo-router (Config & JWKS)<br>• secret/data/orders-service (Kafka)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 530, 140, 380, 80)
    add_node(r10, "n_store", "1", "<b>SecretStore: vault-secret-store</b><br>• API: external-secrets.io/v1<br>• Auth: Kubernetes Token SecretRef<br>• Target Server: http://vault.vault.svc:8200<br>• Status: Valid (ReadWrite)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 530, 240, 380, 80)
    add_node(r10, "n_es", "1", "<b>ExternalSecret: microservices-external-secret</b><br>• Refresh Interval: 1h (Auto-reconciliation)<br>• creationPolicy: Merge • deletionPolicy: Retain<br>• Status: SecretSynced (Ready: True)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E8FF;strokeColor=#8B5CF6;strokeWidth=2;fontColor=#4C1D95;fontSize=11;", 530, 340, 380, 80)
    add_node(r10, "n_k8s_sec", "1", "<b>K8s Secret: microservices-secrets</b><br>Merged DB credentials, JWT Secret & Keycloak Client<br>Direct envFrom injection into Spring Boot pods", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 530, 440, 380, 80)

    add_edge(r10, "e_v_ss", "1", "Vault API", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "n_vault_dev", "n_store")
    add_edge(r10, "e_ss_es", "1", "Store Binding", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1.5;", "n_store", "n_es")
    add_edge(r10, "e_es_sec", "1", "Merge Secrets", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=2;", "n_es", "n_k8s_sec")

    # Section 3: Istio Progressive Canary Deployments
    add_node(r10, "c_canary", "1", "<b>🌐 ISTIO CANARY TRAFFIC MANAGEMENT</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 960, 90, 420, 470)
    add_node(r10, "n_vs", "1", "<b>VirtualService: products-service-vs</b><br>• Header Match: x-canary: true ➔ 100% v2<br>• Weight Split: 90% Subset v1 / 10% Subset v2<br>• Retries: 2 attempts (5xx, connect-failure)<br>• Timeout: 5s per try", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 980, 140, 380, 80)
    add_node(r10, "n_dr", "1", "<b>DestinationRule: products-service-dr</b><br>• Host: products-service.staging.svc<br>• Subset v1 (version=v1)<br>• Subset v2 (version=v2)<br>• TrafficPolicy: ISTIO_MUTUAL (mTLS)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;fontColor=#1E3A8A;fontSize=11;", 980, 240, 380, 80)
    add_node(r10, "n_v1", "1", "<b>products-service v1 Pod (90%)</b><br>Stable Release • image: products-service:1.0.0<br>Labels: app=products-service, version=v1", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 980, 340, 380, 70)
    add_node(r10, "n_v2", "1", "<b>products-service v2 Pod (10% + Header)</b><br>Canary Release • image: products-service:1.0.0<br>Labels: app=products-service, version=v2<br>Safe validation before full promotion", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=2;fontColor=#78350F;fontSize=11;", 980, 430, 380, 90)

    add_edge(r10, "e_vs_dr", "1", "Routes to", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1.5;", "n_vs", "n_dr")
    add_edge(r10, "e_dr_v1", "1", "90% Weight", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_dr", "n_v1")
    add_edge(r10, "e_dr_v2", "1", "10% Weight / Header", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#F59E0B;strokeWidth=1.5;", "n_dr", "n_v2")

    # Section 4: Alertmanager Real Routing
    add_node(r10, "c_alerts", "1", "<b>🚨 ALERTING & INCIDENT ROUTING</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#CBD5E1;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#475569;fontSize=12;dashed=1;", 1410, 90, 430, 470)
    add_node(r10, "n_prule", "1", "<b>PrometheusRule (monitoring.coreos.com)</b><br>• Labels: release: kube-prometheus<br>• ServiceDown • HighErrorRate (5xx &gt; 5%)<br>• HighLatency (P95 &gt; 1s) • HighHeapUsage (&gt; 75%)<br>• RedisExporterDown", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;strokeWidth=2;fontColor=#7F1D1D;fontSize=11;", 1430, 140, 390, 80)
    add_node(r10, "n_amc", "1", "<b>AlertmanagerConfig: microservices-alerts</b><br>• API: monitoring.coreos.com/v1alpha1<br>• Namespace: staging (Matches Staging Alerts)<br>• GroupBy: alertname, job, severity", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEE2E2;strokeColor=#EF4444;strokeWidth=2;fontColor=#7F1D1D;fontSize=11;", 1430, 240, 390, 75)
    add_node(r10, "n_local", "1", "<b>Active Local Receiver (Default)</b><br>• default-local-receiver (In-Cluster Alerts)<br>• Zero external dependencies, never fails", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;fontColor=#064E3B;fontSize=11;", 1430, 335, 390, 60)
    add_node(r10, "n_slack", "1", "<b>Slack Notifications (Ready to Enable)</b><br>• Secret: alertmanager-slack-webhook<br>• Channel: #alerts-microservices", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=11;", 1430, 410, 185, 90)
    add_node(r10, "n_jira", "1", "<b>Jira Incident Webhook (Ready)</b><br>• severity: critical ➔ Issue Automation<br>• Direct ticket creation on outage", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE9FE;strokeColor=#8B5CF6;strokeWidth=1.5;fontColor=#4C1D95;fontSize=11;", 1635, 410, 185, 90)

    add_edge(r10, "e_pr_amc", "1", "Firing Alerts", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#EF4444;strokeWidth=1.5;", "n_prule", "n_amc")
    add_edge(r10, "e_amc_loc", "1", "Route Default", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#10B981;strokeWidth=1.5;", "n_amc", "n_local")
    add_edge(r10, "e_amc_slk", "1", "Configured", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#3B82F6;strokeWidth=1;dashed=1;", "n_amc", "n_slack")
    add_edge(r10, "e_amc_jir", "1", "Critical", "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#8B5CF6;strokeWidth=1;dashed=1;", "n_amc", "n_jira")

    # =========================================================================
    # PAGE 11: Multi-Cloud Infrastructure (AWS • Azure • GCP) & CLI Automation Suite
    # =========================================================================
    r11 = create_page("page_multicloud_automation", "11. Multi-Cloud IaC & CLI Automation Suite")
    add_node(r11, "t11", "1", "<b style='font-size:22px;color:#1E293B;'>MULTI-CLOUD INFRASTRUCTURE (AWS • AZURE • GCP) & AUTOMATION SUITE</b><br><span style='font-size:13px;color:#64748B;'>12 Core Cloud Modules Matrix • Unified Platform CLI Orchestrator • Comprehensive DevSecOps Scripts Ecosystem</span>", title_style, 300, 25, 1400, 50)

    # Section 1: Multi-Cloud Provider Modules Matrix
    add_node(r11, "c_aws", "1", "<b>☁️ AMAZON WEB SERVICES (AWS)</b><br><span style='font-size:11px;color:#64748B;'>terraform/modules/aws/ (dev • staging • prod)</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFBEB;strokeColor=#F59E0B;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#78350F;fontSize=12;dashed=1;", 60, 90, 570, 470)
    add_node(r11, "aws_m1", "1", "• <b>Networking:</b> VPC (3 AZs, Private/Public)<br>• <b>Kubernetes:</b> EKS Cluster + Managed Nodes<br>• <b>Database:</b> RDS PostgreSQL 18 (Multi-AZ)<br>• <b>Cache:</b> ElastiCache Redis 7.1 Replication<br>• <b>Messaging:</b> Amazon MSK (Apache Kafka 3.6)<br>• <b>Storage:</b> S3 Assets Bucket (SSE-KMS, Versioning)<br>• <b>Security:</b> AWS KMS (CMK Key & Alias)<br>• <b>Identity:</b> IAM IRSA (OIDC Trust Provider)<br>• <b>Ingress (Model 2):</b> Istio Ingress + Network Load Balancer (NLB L4)<br>• <b>Dual-Origin CDN:</b> CloudFront + WAFv2 (S3 Static SPA + NLB Dynamic API)<br>• <b>Observability:</b> CloudWatch Alarms & Dashboards<br>• <b>DNS:</b> Route53 Zone + Apex Alias to CloudFront + ACM SSL", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#FDE68A;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 80, 150, 530, 390)

    add_node(r11, "c_azure", "1", "<b>☁️ MICROSOFT AZURE CLOUD</b><br><span style='font-size:11px;color:#64748B;'>terraform/modules/azure/ (dev • staging • prod)</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#1E3A8A;fontSize=12;dashed=1;", 660, 90, 570, 470)
    add_node(r11, "azure_m1", "1", "• <b>Networking:</b> VNet + Subnets (AKS & Postgres)<br>• <b>Kubernetes:</b> AKS Cluster (Managed Autoscaling)<br>• <b>Database:</b> Azure PostgreSQL Flexible Server (HA)<br>• <b>Cache:</b> Azure Cache for Redis (TLS 1.2)<br>• <b>Messaging:</b> Azure Event Hubs (Kafka Surface)<br>• <b>Storage:</b> Azure Storage Account (Blob Containers)<br>• <b>Security:</b> Azure Key Vault (Soft-delete, Purge)<br>• <b>Identity:</b> Azure Workload Identity (Federated Creds)<br>• <b>Ingress (Model 2):</b> Istio Ingress + Azure Standard Load Balancer (L4)<br>• <b>Dual-Origin CDN:</b> Front Door Premium (Storage Blob SPA + AKS SLB API)<br>• <b>Observability:</b> Azure Monitor (Log Analytics, App Insights)<br>• <b>DNS:</b> Azure DNS Zone + Custom Apex Records to Front Door", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#BFDBFE;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 680, 150, 530, 390)

    add_node(r11, "c_gcp", "1", "<b>☁️ GOOGLE CLOUD PLATFORM (GCP)</b><br><span style='font-size:11px;color:#64748B;'>terraform/modules/gcp/ (dev • staging • prod)</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#064E3B;fontSize=12;dashed=1;", 1260, 90, 580, 470)
    add_node(r11, "gcp_m1", "1", "• <b>Networking:</b> Google Cloud VPC + Cloud NAT<br>• <b>Kubernetes:</b> GKE Autopilot Cluster<br>• <b>Database:</b> Cloud SQL PostgreSQL 18 (HA)<br>• <b>Cache:</b> Cloud Memorystore for Redis 7.2<br>• <b>Messaging:</b> Managed Kafka / Cloud PubSub & DLQ<br>• <b>Storage:</b> Google Cloud Storage (CMEK, Uniform Access)<br>• <b>Security:</b> Google Cloud KMS (KeyRing & CryptoKey)<br>• <b>Identity:</b> GCP Workload Identity (GSA to KSA)<br>• <b>Ingress (Model 2):</b> Istio Ingress + Passthrough Network Load Balancer (L4)<br>• <b>Dual-Origin CDN:</b> Cloud Armor + Cloud CDN (GCS Bucket SPA + Istio NLB API)<br>• <b>Observability:</b> Cloud Monitoring (Dashboards & Alerts)<br>• <b>DNS:</b> Cloud DNS Managed Zone + Global A-Record to Load Balancer", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#A7F3D0;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 1280, 150, 540, 390)

    # Section 2: Unified Platform CLI Orchestrator
    add_node(r11, "c_cli", "1", "<b>🚀 UNIFIED PLATFORM CLI ORCHESTRATOR (.\\platform.ps1)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#1E293B;fontSize=12;dashed=1;", 60, 580, 880, 340)
    add_node(r11, "cli_commands", "1", "• <code>.\\platform.ps1 up [-Platform minikube|aws|azure|gcp] [-Environment dev|staging|prod]</code>: Multi-platform bootstrap<br>• <code>.\\platform.ps1 doctor [-Platform <name>]</code>: Deep diagnostic health audit of pods, nodeports, metrics and OPA policies<br>• <code>.\\platform.ps1 cost [-Environment minikube|staging|prod]</code>: Air-gapped FinOps cost breakdown and savings calculator<br>• <code>.\\platform.ps1 tools [-Install]</code>: Fast audit (<1s) & Winget installation of 17 DevSecOps, IaC and K8s tools<br>• <code>.\\platform.ps1 rollback [-Platform <name>] [-LockId <id>]</code>: Automated emergency state unlock and deployment rollback<br>• <code>.\\platform.ps1 plan / apply [-Platform <name>]</code>: Multi-cloud Terraform infrastructure provisioning<br>• <code>.\\platform.ps1 urls</code>: Interactive live table of all active frontend, API, IAM, and observability endpoints<br>• <code>.\\platform.ps1 smoke / tunnels / secrets / graph / diagrams</code>: Verification, background tunnels, CSPRNG secrets & Drawio sync<br>• <code>.\\platform.ps1 down / destroy [-Destroy]</code>: Graceful resource pause or complete multi-cloud / Minikube purge", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 80, 630, 840, 270)

    # Section 3: Scripts Ecosystem Directory Map
    add_node(r11, "c_scripts", "1", "<b>📂 AUTOMATION SCRIPTS PORTFOLIO (scripts/)</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#1E293B;fontSize=12;dashed=1;", 960, 580, 880, 340)
    add_node(r11, "scripts_map", "1", "• <b>Unified Master CLI:</b> platform.ps1 (Multi-cloud bootstrap, plan, apply, doctor, cost, rollback)<br>• <b>scripts/bootstrap-keycloak.ps1:</b> Native Keycloak 26 realm & PKCE/M2M client bootstrapper<br>• <b>scripts/build-all.py:</b> Concurrent Maven + React container image compiler<br>• <b>scripts/endpoint-smoke-test.py:</b> Synthetic post-deployment health & latency SLO validator<br>• <b>scripts/generate-secure-secrets.py:</b> High-entropy CSPRNG credential & JWT secret generator<br>• <b>scripts/local-cost-estimator.py:</b> Air-gapped FinOps cost model and local savings calculator<br>• <b>scripts/supervise-tunnels.py:</b> Resilient background port-forwarding supervisor daemon<br>• <b>scripts/update_dashboards.py:</b> Programmatic Grafana dashboard JSON synchronizer<br>• <b>scripts/generate_drawio.py:</b> 12-page mathematical architectural blueprint generator<br>• <b>scripts/testing/:</b> simulate.py (Traffic, DDoS, Chaos), smoke.py, verify.py, check.py, test_order.py", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 980, 630, 840, 270)

    # Section 4: Bottom Banner
    add_node(r11, "ops_box_11", "1", "<b>🎯 ENTERPRISE PLATFORM SUMMARY</b>: True cloud-agnostic architecture offering identical 12-tier functionality across AWS, Azure, and GCP, fully operational locally on Minikube with 100% cloud parity, zero cloud costs, and managed by a single unified CLI entrypoint.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#475569;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 60, 940, 1780, 60)

    # =========================================================================
    # PAGE 12: Multi-Cloud CI/CD & Automated Rollback Architecture
    # =========================================================================
    r12 = create_page("page_cicd_rollback_arch", "12. Multi-Cloud CI/CD & Automated Rollback Architecture")
    add_node(r12, "t12", "1", "<b style='font-size:22px;color:#1E293B;'>MULTI-CLOUD CI/CD & AUTOMATED ROLLBACK ARCHITECTURE</b><br><span style='font-size:13px;color:#64748B;'>GitHub Actions (CI) + ArgoCD (CD) • Azure DevOps (Unified 12+ Stages) • Bitbucket Pipelines (Unified 12+ Stages) • Emergency Rollback Engines</span>", title_style, 300, 25, 1400, 50)

    # Column 1: GitHub Actions + ArgoCD (Decoupled Model)
    add_node(r12, "c_gha_argo", "1", "<b>🐙 GITHUB ACTIONS (CI) + ARGOCD (CD)</b><br><span style='font-size:11px;color:#64748B;'>AWS EKS & Minikube Ecosystem</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFBEB;strokeColor=#F59E0B;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#78350F;fontSize=12;dashed=1;", 60, 90, 570, 500)
    add_node(r12, "gha_ci_box", "1", "<b>GitHub Actions (Strictly CI - Stages 1-5):</b><br>• 1. Unit Tests (Maven/React, JaCoCo Coverage)<br>• 2. SAST & Secrets (Gitleaks + Semgrep Rules)<br>• 3. Build Container & CycloneDX SBOM (Trivy)<br>• 4. Container Vulnerability Scan (Trivy CRITICAL/HIGH)<br>• 5. Compliance & Policy Gate (Conftest / OPA)<br>• 6. Certified Image Push to AWS ECR<br>• 7. Trigger ArgoCD GitOps Sync via CLI/API", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#FDE68A;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 80, 150, 530, 140)
    add_node(r12, "argo_cd_box", "1", "<b>ArgoCD (Strictly CD - Stages 6-12+):</b><br>• <b>develop:</b> <code>application-dev.yaml</code> ➔ Minikube (<code>dev</code> ns)<br>• <b>staging:</b> <code>application-staging.yaml</code> ➔ AWS EKS (<code>staging</code> ns)<br>  (Medium Perf: 2 replicas, 250m-500m CPU, 512Mi-1024Mi RAM)<br>• <b>main/master:</b> <code>application-prod.yaml</code> ➔ AWS EKS (<code>production</code> ns)<br>  (High Perf: HPA 3-10 replicas, Istio Canary 90/10, ALB Ingress)<br>• <b>Automated Rollback:</b> <code>argocd app rollback</code> on sync/health fail<br>• <b>State Recovery:</b> AWS Terraform state lock release on error", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#FDE68A;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 80, 310, 530, 160)
    add_node(r12, "argo_roll_box", "1", "<b>🔄 Automated Rollback Engine:</b><br>• Automatic retry backoff (5 attempts, factor 2)<br>• Instant fallback to previous healthy ReplicaSet on Pod CrashLoop<br>• State lock release: <code>terraform force-unlock</code> on S3/DynamoDB", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=10;align=left;spacingLeft=10;", 80, 490, 530, 80)

    # Column 2: Azure DevOps (Single Unified Pipeline)
    add_node(r12, "c_azdo", "1", "<b>🔷 AZURE DEVOPS (SINGLE UNIFIED PIPELINE)</b><br><span style='font-size:11px;color:#64748B;'>Azure Cloud & AKS Ecosystem</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#1E3A8A;fontSize=12;dashed=1;", 660, 90, 570, 500)
    add_node(r12, "azdo_stages", "1", "<b>Single Pipeline Covering All 12+ Stages:</b><br>• 1. Maven / React Tests & JaCoCo Coverage<br>• 2. SAST (Semgrep, Gitleaks, Checkov, SonarQube)<br>• 3. BuildKit Image Build & CycloneDX SBOM<br>• 4. Aqua Trivy Image Vulnerability Scan<br>• 5. Conftest / OPA Kubernetes Manifest Verification<br>• <b>Stage 5.5:</b> Deploy AKS Dev (branch <code>develop</code>, ns <code>dev</code>) + <b>RollbackDev</b><br>• 6. Deploy AKS Staging (branch <code>staging</code>/PR, ns <code>staging</code>)<br>• 7-10. Newman QA, Cypress E2E, k6 Latency, OWASP ZAP DAST<br>• <b>RollbackStaging:</b> Automated Helm rollback on test failure<br>• 11. Certified Image Promotion & Push to ACR<br>• 12. Deploy AKS Production (Istio Canary 90/10, ns <code>production</code>)<br>• <b>RollbackProduction:</b> Emergency rollback & Istio route restore", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#BFDBFE;strokeWidth=1.5;fontColor=#1E293B;fontSize=10.5;align=left;spacingLeft=15;", 680, 150, 530, 240)
    add_node(r12, "azdo_tf_box", "1", "<b>Terraform Azure Pipeline (azure-pipelines-terraform.yml):</b><br>• Triggers on <code>develop</code>, <code>staging</code>, <code>main</code>, <code>master</code><br>• Dynamic workspace selection: <code>dev</code>, <code>staging</code>, <code>prod</code><br>• Automatic AKS namespace provisioning (<code>dev</code>, <code>staging</code>, <code>production</code>)<br>• Automated lease unlock and recovery on Azure Storage backend", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#BFDBFE;strokeWidth=1.5;fontColor=#1E293B;fontSize=10.5;align=left;spacingLeft=15;", 680, 410, 530, 160)

    # Column 3: Bitbucket Pipelines (Single Unified Pipeline)
    add_node(r12, "c_bb", "1", "<b>🪣 BITBUCKET PIPELINES (SINGLE UNIFIED PIPELINE)</b><br><span style='font-size:11px;color:#64748B;'>Google Cloud Platform & GKE Ecosystem</span>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#064E3B;fontSize=12;dashed=1;", 1260, 90, 580, 500)
    add_node(r12, "bb_stages", "1", "<b>Single Pipeline Covering All 12+ Stages:</b><br>• <b>develop:</b> CI (1-5) ➔ GCP Terraform Dev (ws <code>dev</code>) ➔ GKE Dev Deploy (ns <code>dev</code>) ➔ <b>rollback-gke-dev</b> on error<br>• <b>staging:</b> CI (1-5) ➔ GCP Terraform Staging (ws <code>staging</code>, Medium Perf) ➔ GKE Staging Deploy (ns <code>staging</code>) ➔ QA Validation (Newman, Cypress, k6, ZAP DAST) ➔ GAR Push ➔ <b>rollback-gke-staging</b> on test fail<br>• <b>main / master:</b> CI (1-5) ➔ GCP Terraform Prod (ws <code>prod</code>, High Perf HA) ➔ Pre-flight QA ➔ GAR Push ➔ GKE Production Canary (Istio 90/10) ➔ <b>rollback-gke-production</b> on rollout fail", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#A7F3D0;strokeWidth=1.5;fontColor=#1E293B;fontSize=10.5;align=left;spacingLeft=15;", 1280, 150, 540, 240)
    add_node(r12, "bb_tf_box", "1", "<b>Terraform GCP Provisioning & Automation:</b><br>• Parameterized steps: <code>terraform-gcp-dev</code>, <code>staging</code>, <code>prod</code><br>• Managed GKE Autopilot, Cloud SQL HA, Memorystore Redis<br>• Automated GCS backend state force-unlock on apply failure<br>• Istio VirtualService Canary fallback to baseline subset v1", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#A7F3D0;strokeWidth=1.5;fontColor=#1E293B;fontSize=10.5;align=left;spacingLeft=15;", 1280, 410, 540, 160)

    # Section 2: Automated Rollback Matrix
    add_node(r12, "c_roll_matrix", "1", "<b>🛡️ AUTOMATED ROLLBACK & INCIDENT RECOVERY MATRIX</b>", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F8FAFC;strokeColor=#64748B;strokeWidth=2;verticalAlign=top;align=left;spacingLeft=15;spacingTop=10;fontColor=#1E293B;fontSize=12;dashed=1;", 60, 610, 1780, 290)
    add_node(r12, "rm_1", "1", "<b>Level 1: IaC State Lock Release</b><br>• Auto-triggers on apply failure<br>• Releases DynamoDB / Azure Blob / GCS state lock<br>• Prevents frozen CI/CD pipelines", "rounded=1;whiteSpace=wrap;html=1;fillColor=#EFF6FF;strokeColor=#3B82F6;strokeWidth=1.5;fontColor=#1E3A8A;fontSize=11;align=left;spacingLeft=15;", 80, 660, 410, 110)
    add_node(r12, "rm_2", "1", "<b>Level 2: Automated GitOps Rollback</b><br>• ArgoCD CLI app rollback<br>• Reverts to previous certified Git revision<br>• SelfHeal restores desired cluster state", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FDF2F8;strokeColor=#EC4899;strokeWidth=1.5;fontColor=#831843;fontSize=11;align=left;spacingLeft=15;", 520, 660, 410, 110)
    add_node(r12, "rm_3", "1", "<b>Level 3: Helm Atomic Rollback</b><br>• Executes <code>helm rollback</code> on QA failure<br>• Protects <code>dev</code>, <code>staging</code>, and <code>production</code><br>• Zero residual orphaned resources", "rounded=1;whiteSpace=wrap;html=1;fillColor=#ECFDF5;strokeColor=#10B981;strokeWidth=1.5;fontColor=#064E3B;fontSize=11;align=left;spacingLeft=15;", 960, 660, 410, 110)
    add_node(r12, "rm_4", "1", "<b>Level 4: Istio Canary Shift Abort</b><br>• Health probe failure triggers 100% v1 shift<br>• Re-applies baseline DestinationRule & VS<br>• Customer-facing traffic unaffected (&lt;1s)", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FEF3C7;strokeColor=#F59E0B;strokeWidth=1.5;fontColor=#78350F;fontSize=11;align=left;spacingLeft=15;", 1400, 660, 420, 110)

    add_node(r12, "rm_banner", "1", "<b>🎯 ZERO DOWNTIME & SELF-HEALING ASSURANCE:</b> Every pipeline tier is fully guarded by automated rollback. Failure at any test gate (Newman, Cypress, k6, ZAP DAST, or Canary health) immediately triggers automated cluster rollback, releases Terraform state locks, and resets Istio traffic routing to the certified baseline release.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#CBD5E1;strokeWidth=1.5;fontColor=#1E293B;fontSize=11;align=left;spacingLeft=15;", 80, 790, 1740, 90)

    # Section 3: Summary Banner
    add_node(r12, "ops_box_12", "1", "<b>🎯 MULTI-CLOUD CI/CD SUMMARY</b>: GitHub Actions strictly governs CI while ArgoCD operates declarative CD. Azure DevOps and Bitbucket Pipelines execute single unified pipelines with all 12+ stages, multi-cloud Terraform provisioning across dev/staging/prod workspaces, and fully automated rollback engines.", "rounded=1;whiteSpace=wrap;html=1;fillColor=#F1F5F9;strokeColor=#475569;strokeWidth=2;fontColor=#1E293B;fontSize=12;align=left;spacingLeft=20;", 60, 920, 1780, 60)

    tree = ET.ElementTree(root_mxfile)
    ET.indent(tree, space="  ", level=0)
    tree.write("docs/Diagrams.drawio", encoding="utf-8", xml_declaration=True)
    print("Successfully generated docs/Diagrams.drawio in English with 12 comprehensive tabs!")

if __name__ == "__main__":
    build_drawio_xml()

