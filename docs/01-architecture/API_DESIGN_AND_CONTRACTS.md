# 📐 Enterprise API Design & Contract Standards

> [!TIP]
> 🧭 **[Enterprise Platform Hub](../../README.md)** > **01. Architecture** > `API_DESIGN_AND_CONTRACTS.md`

This guide formalizes the architectural contracts, REST standards, **RFC 7807 Problem Details**, and **GraphQL Federation v2** schemas enforced across the microservices ecosystem.

---

## 🏛️ Dual-Interface API Strategy: GraphQL Federation + REST

The platform adopts a hybrid dual-interface architecture:

```mermaid
graph TD
    Client[Storefront / Mobile / Third-Party] -->|GraphQL Queries & Mutations| Router[Cosmo Router Gateway :8080]
    Client -->|Direct REST Fallback / Webhooks| Router
    
    subgraph "Federated Supergraph"
        Router -->|Federated Query| SubProducts[Products Subgraph :8004/graphql]
        Router -->|Federated Query| SubOrders[Orders Subgraph :8003/graphql]
        Router -->|Federated Query| SubInventory[Inventory Subgraph :8001/graphql]
    end

    subgraph "Direct REST Endpoints (OpenAPI 3.0)"
        Router -.->|REST Proxy| RestProducts[Products REST :8004/api/product]
        Router -.->|REST Proxy| RestOrders[Orders REST :8003/api/order]
        Router -.->|REST Proxy| RestInventory[Inventory REST :8001/api/inventory]
        Router -.->|REST / SSE| RestNotify[Notification REST :8002/api/notifications]
    end
```

1. **GraphQL Federation v2 (External/BFF):** Consumed by the React 19 Storefront for low-latency batch fetching and single-roundtrip aggregations.
2. **RESTful APIs with OpenAPI 3.0 (Internal/Automation):** Consumed by Newman contract tests, automated webhooks, health checks, and service-to-service communication.

---

## 📜 RESTful Resource & URL Conventions

All REST endpoints adhere to strict RESTful URL design rules:

| Category | Convention | Good Example | Anti-Pattern (Avoid) |
| :--- | :--- | :--- | :--- |
| **Resources** | Plural nouns, lowercase, kebab-case | `/api/product`, `/api/order` | `/api/getProducts`, `/api/create_order` |
| **Identifiers** | Path parameters for entity lookup | `/api/inventory/{sku}`, `/api/order/{id}` | `/api/inventory?sku=XYZ` |
| **Sub-Resources** | Nested hierarchical paths | `/api/order/{id}/items` | `/api/getOrderItems?orderId=123` |
| **Actions** | Controller sub-paths using verbs | `/api/order/{id}/cancel` | `/api/cancelOrder/{id}` |

---

## 📄 Standard Pagination & Filtering Contract

Endpoints returning collections support deterministic pagination using standard query parameters:

```http
GET /api/product?pageNumber=0&pageSize=20&sort=name,asc
```

### Query Parameters:
* `pageNumber` *(integer, default: 0)*: Zero-indexed page number.
* `pageSize` *(integer, default: 20, max: 100)*: Number of items per page.
* `sort` *(string, optional)*: Field name followed by direction (e.g. `price,desc`).

### Standard Paged Response Schema (OpenAPI 3.0):
```json
{
  "content": [
    {
      "id": 1,
      "sku": "SKU-TECH-001",
      "name": "Mechanical Keyboard",
      "price": 129.99,
      "currency": "USD",
      "status": true
    }
  ],
  "pageable": {
    "pageNumber": 0,
    "pageSize": 20,
    "offset": 0
  },
  "totalElements": 48,
  "totalPages": 3,
  "last": false,
  "first": true,
  "empty": false
}
```

---

## 🛡️ Universal Error Handling: RFC 7807 (Problem Details)

All microservices implement **RFC 7807 Problem Details** via a centralized `GlobalExceptionHandler`. Unhandled exceptions never leak raw stack traces to clients.

### RFC 7807 Payload Structure:
```json
{
  "type": "https://api.microservices.example.com/errors/insufficient-stock",
  "title": "Insufficient Stock",
  "status": 409,
  "detail": "Requested quantity (10) exceeds available stock (3) for SKU: SKU-TECH-001.",
  "instance": "/api/order",
  "timestamp": "2026-10-02T14:10:00Z"
}
```

### Validation Error Payload (`400 Bad Request`):
When input constraints fail (`@Valid` / `MethodArgumentNotValidException`), all microservices return structured field violations with an aggregated human-readable summary string:

```json
{
  "timestamp": "2026-10-15T22:00:00Z",
  "status": 400,
  "error": "Validation Failed",
  "message": "sku: sku must match ^[A-Z0-9\\-]{6,20}$; name: name cannot exceed 150 characters",
  "fields": {
    "sku": "sku must match ^[A-Z0-9\\-]{6,20}$",
    "name": "name cannot exceed 150 characters"
  }
}
```

* **Client Resiliency:** The React frontend extracts violations via `extractApiErrorMessage()`, surfacing precise field-level feedback directly in notification toasts rather than masking errors with generic titles.
* **Catalog Validation Regex Rules:**
  * **Product SKU:** `^[A-Z0-9\-]{6,20}$` (strictly 6 to 20 uppercase alphanumeric or hyphen characters).
  * **Product Name:** `^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9.,'\-()\"/&+%:#!*[\\] ]+$` (allows standard tech product punctuation such as quotes, slashes, plus, and brackets while preventing XSS vectors; max 150 characters).

### HTTP Status Code Mapping:
| HTTP Status | Exception Class | RFC 7807 Title | Scenario |
| :---: | :--- | :--- | :--- |
| **400 Bad Request** | `MethodArgumentNotValidException` | Validation Failed | Field constraint violations (`fields` map + `message` summary). |
| **401 Unauthorized** | `AuthenticationException` | Unauthorized | Missing or expired JWT bearer token. |
| **403 Forbidden** | `AccessDeniedException` | Forbidden | Standard user attempting to cancel another customer's order. |
| **404 Not Found** | `ProductNotFoundException`, `OrderNotFoundException` | Resource Not Found | Target entity does not exist in domain repository. |
| **409 Conflict** | `InsufficientStockException` | Domain Conflict | Concurrency collision or insufficient warehouse inventory. |
| **503 Service Unavailable** | `ServiceUnavailableException` | Downstream Outage | Circuit breaker open on downstream dependency. |

---

## 📷 Agnostic POS QR & Barcode Scanner Architecture

The storefront integrates an enterprise **Point-of-Sale (POS) Scanner Engine** designed for omnichannel operations (WebCam streaming, image upload/dropzone, and hardware USB/Bluetooth laser readers):

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Store Associate / Admin
    participant Scanner as POS Modal (React 19 + jsQR)
    participant Products as products-service (:8004)
    participant Inventory as inventory-service (:8001)
    participant Orders as orders-service (:8003)
    participant Router as Cosmo Router (:8080)

    Admin->>Scanner: Point camera or scan label / receipt
    alt BarcodeDetector Available
        Scanner->>Scanner: Native hardware decoding
    else Browser Fallback
        Scanner->>Scanner: Offscreen canvas + jsQR software decoding
    end
    
    alt Scanned SKU / Product Label
        Scanner->>Inventory: GET /api/inventory/detail/{sku}
        Inventory-->>Scanner: 200 OK (PostgreSQL live stock units)
        Scanner->>Scanner: Display live stock & Add to Cart
        opt Admin Stock Correction
            Admin->>Scanner: Click '+1 Stock'
            Scanner->>Inventory: PUT /api/inventory/{sku}?quantity={newQty}
            Inventory-->>Scanner: 200 OK (Stock updated)
        end
    else Scanned Order Receipt (ORD-*)
        Scanner->>Router: GraphQL query { orders { ... } }
        Router->>Orders: Federated query
        Orders-->>Scanner: Order details (STATUS, items, tracking)
        opt Admin Order Fulfillment
            Admin->>Scanner: Click 'Ship Order'
            Scanner->>Router: mutation { shipOrder(id: $id) }
            Router->>Orders: Update status to SHIPPED & publish Kafka event
        end
    end
    Scanner--)Orders: Async Telemetry POST /api/order/funnel (QR_SCAN_RESOLVED)
```

### Key Capabilities:
1. **Universal Dual-Engine Decoding:** Native `BarcodeDetector` API supplemented with pure TypeScript `jsQR` offscreen canvas processing, guaranteeing 100% scanning support across Chrome, Firefox, Edge, Safari, iOS, and Android.
2. **Authoritative Stock Verification:** Queries `GET /api/inventory/detail/{sku}` directly against PostgreSQL to prevent stale client cache anomalies.
3. **In-Modal POS Fulfillment:** Administrators can trigger order fulfillment (`shipOrder`, `deliverOrder`) directly from the scanner view upon reading shipping labels or order receipts.
4. **Security Header Alignment:** Serves `Permissions-Policy: camera=(self), microphone=(), geolocation=()` via Nginx, allowing WebCam access for the storefront origin while restricting unauthorized third-party embeds.

---

## 🧩 Apollo Federation v2 Schema Directives

Each microservice exposes a federated subgraph schema:

```graphql
extend schema
  @link(url: "https://specs.apollo.dev/federation/v2.3",
        import: ["@key", "@shareable", "@external", "@provides"])

type Product @key(fields: "id") {
  id: ID!
  sku: String!
  name: String!
  price: Float!
  inventory: InventoryStock @provides(fields: "quantity")
}

type Order @key(fields: "id") {
  id: ID!
  orderNumber: String!
  userId: String!
  status: OrderStatus!
  items: [OrderItem!]!
}
```

---

## 🧪 Contract Testing & Automated Verification

API contracts are continuously verified in CI/CD pipelines via:
* **Newman Automated Contract Suite:** [`devsecops/testing/newman/microservices.postman_collection.json`](../../devsecops/testing/newman/microservices.postman_collection.json) executes 23 requests and 47 assertions covering both public and authenticated flows.
* **SpringDoc Swagger UI:** Available locally at `http://localhost:<port>/swagger-ui.html` and `http://localhost:<port>/v3/api-docs` on every microservice.
* **Cosmo Supergraph Execution Config:** Stored in [`helm/charts/cosmo-router/files/execution-config.json`](../../helm/charts/cosmo-router/files/execution-config.json).
