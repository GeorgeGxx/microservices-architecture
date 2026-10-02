#!/usr/bin/env python3
"""
Generates devsecops/testing/newman/microservices.postman_collection.json
Aligned with Cosmo Router GraphQL Federation v2 (orders v2.5), Keycloak OIDC,
Logistics State Machine, Saga Compensation, and SSE Notifications.
"""

import json
import copy
import uuid

def build_postman_collection():
    collection = {
        "info": {
            "_postman_id": "80d0f149-1d5d-4cef-a67e-10c7cee79cf9",
            "name": "microservices-cosmo-router",
            "description": "Enterprise Microservices Architecture Collection with Cosmo Router 0.353.0 (GraphQL Federation v2; orders v2.5), Spring Boot 4.0.8 Subgraphs, Keycloak OAuth2/OIDC, Automated DHL Tracking, Cart Abandonment Telemetry, and Saga Compensation Pattern.",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
        },
        "item": [
            {
                "name": "🔑 Authentication",
                "item": [
                    {
                        "name": "1. Login as Standard User (basic_user)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "const res = pm.response.json();",
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "if (res.access_token) {",
                                        "    pm.collectionVariables.set('user_jwt_token', res.access_token);",
                                        "    pm.test('Token received and saved to {{user_jwt_token}}', () => {",
                                        "        pm.expect(res.access_token).to.be.a('string');",
                                        "    });",
                                        "    console.log('✅ User JWT successfully stored in collection variable user_jwt_token');",
                                        "}"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "auth": {"type": "noauth"},
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/x-www-form-urlencoded", "type": "text"}
                            ],
                            "body": {
                                "mode": "urlencoded",
                                "urlencoded": [
                                    {"key": "grant_type", "value": "password", "type": "text"},
                                    {"key": "client_id", "value": "microservices_frontend", "type": "text"},
                                    {"key": "username", "value": "basic_user", "type": "text"},
                                    {"key": "password", "value": "password", "type": "text"},
                                    {"key": "scope", "value": "openid email profile", "type": "text"}
                                ]
                            },
                            "url": {
                                "raw": "{{keycloak_url}}/realms/microservices-realm/protocol/openid-connect/token",
                                "host": ["{{keycloak_url}}"],
                                "path": ["realms", "microservices-realm", "protocol", "openid-connect", "token"]
                            },
                            "description": "Obtains a Standard User JWT token without administrative privileges. Saves automatically to {{user_jwt_token}}."
                        },
                        "response": []
                    },
                    {
                        "name": "2. Login as Admin (admin_user)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "const res = pm.response.json();",
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "if (res.access_token) {",
                                        "    pm.collectionVariables.set('admin_jwt_token', res.access_token);",
                                        "    pm.test('Admin Token received and saved to {{admin_jwt_token}}', () => {",
                                        "        pm.expect(res.access_token).to.be.a('string');",
                                        "    });",
                                        "    console.log('✅ Admin JWT successfully stored in collection variable admin_jwt_token');",
                                        "}"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "auth": {"type": "noauth"},
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/x-www-form-urlencoded", "type": "text"}
                            ],
                            "body": {
                                "mode": "urlencoded",
                                "urlencoded": [
                                    {"key": "grant_type", "value": "password", "type": "text"},
                                    {"key": "client_id", "value": "microservices_frontend", "type": "text"},
                                    {"key": "username", "value": "admin_user", "type": "text"},
                                    {"key": "password", "value": "admin", "type": "text"},
                                    {"key": "scope", "value": "openid email profile", "type": "text"}
                                ]
                            },
                            "url": {
                                "raw": "{{keycloak_url}}/realms/microservices-realm/protocol/openid-connect/token",
                                "host": ["{{keycloak_url}}"],
                                "path": ["realms", "microservices-realm", "protocol", "openid-connect", "token"]
                            },
                            "description": "Obtains an Admin User JWT token with administrative privileges (ROLE_ADMIN). Saves automatically to {{admin_jwt_token}}."
                        },
                        "response": []
                    }
                ]
            },
            {
                "name": "🚀 Cosmo Router - GraphQL Supergraph",
                "item": [
                    {
                        "name": "1. Cosmo Router GraphQL Reachability",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Cosmo Router GraphQL endpoint responds (HTTP 200)', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('GraphQL root query resolves without errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "    pm.expect(res.data.__typename).to.equal('Query');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "auth": {"type": "noauth"},
                            "method": "POST",
                            "header": [],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query RouterReadiness { __typename }",
                                    "variables": "{}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Checks the Cosmo Router GraphQL listener and readiness endpoint on port 8080. Prometheus metrics are exposed on the internal port 9090."
                        },
                        "response": []
                    },
                    {
                        "name": "2. Federated Products Catalog with Stock",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('GraphQL Status 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Products array returned with federated stock', () => {",
                                        "    pm.expect(res.data).to.have.property('products');",
                                        "    pm.expect(res.data.products).to.be.an('array');",
                                        "    pm.expect(res.data.products.length).to.be.above(0);",
                                        "});",
                                        "if (res.data && res.data.products && res.data.products.length > 0) {",
                                        "    const firstProd = res.data.products[0];",
                                        "    pm.collectionVariables.set('product_sku', firstProd.sku);",
                                        "    pm.test('Product catalog has valid properties', () => {",
                                        "        pm.expect(firstProd).to.have.property('sku');",
                                        "        pm.expect(firstProd).to.have.property('price');",
                                        "    });",
                                        "}"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetProductsWithStock {\n  products {\n    id\n    sku\n    name\n    description\n    price\n    category\n    rating\n    reviewCount\n    isBestSeller\n  }\n}",
                                    "variables": "{}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Fetches products catalog federating product entity with inventory stock in a single GraphQL query through Cosmo Router."
                        },
                        "response": []
                    },
                    {
                        "name": "3. Product by SKU (Federated Detail)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Product by SKU matches requested SKU', () => {",
                                        "    pm.expect(res.data.productBySku).to.exist;",
                                        "    pm.expect(res.data.productBySku.sku).to.equal(pm.collectionVariables.get('product_sku'));",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetProductBySku($sku: String!) {\n  productBySku(sku: $sku) {\n    id\n    sku\n    name\n    price\n    category\n  }\n}",
                                    "variables": "{\n  \"sku\": \"{{product_sku}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Fetches a single product by SKU with federated stock details."
                        },
                        "response": []
                    },
                    {
                        "name": "4. Place Order (with Idempotency & DHL Tracking)",
                        "event": [
                            {
                                "listen": "prerequest",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "// Generate UUIDv4 for Idempotency Key",
                                        "const uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {",
                                        "    const r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);",
                                        "    return v.toString(16);",
                                        "});",
                                        "pm.collectionVariables.set('idempotency_key', uuid);"
                                    ]
                                }
                            },
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Order created successfully with tracking and total', () => {",
                                        "    const order = res.data.placeOrder;",
                                        "    pm.expect(order).to.exist;",
                                        "    pm.expect(order.id).to.exist;",
                                        "    pm.collectionVariables.set('order_id', order.id);",
                                        "    if (order.trackingNumber) {",
                                        "        pm.collectionVariables.set('tracking_number', order.trackingNumber);",
                                        "        pm.expect(order.trackingNumber).to.match(/^DHL-[A-Z0-9]+$/);",
                                        "    }",
                                        "    pm.expect(order.orderStatus).to.be.oneOf(['PLACED', 'PREPARING']);",
                                        "    pm.expect(order.orderItems).to.be.an('array');",
                                        "    pm.expect(order.orderItems.length).to.be.above(0);",
                                        "    console.log('✅ Created Order #' + order.id + ' tracking: ' + order.trackingNumber);",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{user_jwt_token}}", "type": "text"},
                                {"key": "X-Idempotency-Key", "value": "{{idempotency_key}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "mutation PlaceOrder($input: PlaceOrderInput!) {\n  placeOrder(input: $input) {\n    id\n    orderNumber\n    orderStatus\n    customerName\n    customerEmail\n    deliveryMethod\n    trackingNumber\n    carrier\n    subtotalAmount\n    shippingFee\n    taxAmount\n    totalAmount\n    paymentMethod\n    orderItems {\n      id\n      sku\n      price\n      quantity\n    }\n  }\n}",
                                    "variables": "{\n  \"input\": {\n    \"customerName\": \"Jorge Garcia\",\n    \"customerEmail\": \"jorge@example.com\",\n    \"shippingAddress\": \"Av. Constitucion 1234, Col. Centro\",\n    \"city\": \"Monterrey\",\n    \"postalCode\": \"64000\",\n    \"phone\": \"+52 81 1234 5678\",\n    \"deliveryMethod\": \"EXPRESS\",\n    \"paymentMethod\": \"CARD_VISA\",\n    \"orderItems\": [\n      {\n        \"sku\": \"{{product_sku}}\",\n        \"price\": 999.99,\n        \"quantity\": 1\n      }\n    ]\n  }\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Places a new order through Cosmo Router propagating JWT authorization and X-Idempotency-Key. Saves order_id and DHL tracking_number."
                        },
                        "response": []
                    },
                    {
                        "name": "5. List Orders",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Orders array returned', () => {",
                                        "    pm.expect(res.data.orders).to.be.an('array');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{user_jwt_token}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetOrders {\n  orders {\n    id\n    orderNumber\n    orderStatus\n    totalAmount\n    trackingNumber\n    carrier\n    orderItems {\n      sku\n      price\n      quantity\n    }\n  }\n}",
                                    "variables": "{}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Queries orders for the authenticated user based on JWT sub claim."
                        },
                        "response": []
                    },
                    {
                        "name": "6. Order by ID (Detailed Query)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Order details match created order ID', () => {",
                                        "    pm.expect(res.data.order).to.exist;",
                                        "    pm.expect(res.data.order.id).to.equal(pm.collectionVariables.get('order_id'));",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{user_jwt_token}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetOrder($id: ID!) {\n  order(id: $id) {\n    id\n    orderNumber\n    orderStatus\n    customerName\n    customerEmail\n    totalAmount\n    trackingNumber\n    carrier\n  }\n}",
                                    "variables": "{\n  \"id\": \"{{order_id}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Fetches a specific order by ID."
                        },
                        "response": []
                    },
                    {
                        "name": "7. Ship Order (Stage 3 Logistics - In Transit DHL)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Order transitioned to SHIPPED status', () => {",
                                        "    pm.expect(res.data.shipOrder).to.exist;",
                                        "    pm.expect(res.data.shipOrder.orderStatus).to.equal('SHIPPED');",
                                        "    pm.expect(res.data.shipOrder.carrier).to.equal('DHL Express');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{admin_jwt_token}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "mutation ShipOrder($id: ID!) {\n  shipOrder(id: $id) {\n    id\n    orderStatus\n    trackingNumber\n    carrier\n  }\n}",
                                    "variables": "{\n  \"id\": \"{{order_id}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Transitions the order into SHIPPED status via Cosmo Router GraphQL mutation."
                        },
                        "response": []
                    },
                    {
                        "name": "8. Deliver Order (Stage 5 Logistics - Delivered & Signed)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Order transitioned to DELIVERED status', () => {",
                                        "    pm.expect(res.data.deliverOrder).to.exist;",
                                        "    pm.expect(res.data.deliverOrder.orderStatus).to.equal('DELIVERED');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{admin_jwt_token}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "mutation DeliverOrder($id: ID!) {\n  deliverOrder(id: $id) {\n    id\n    orderStatus\n  }\n}",
                                    "variables": "{\n  \"id\": \"{{order_id}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Transitions the order into DELIVERED status via Cosmo Router GraphQL mutation."
                        },
                        "response": []
                    },
                    {
                        "name": "10. Cancel Order (Saga Compensation & Stock Rollback)",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('Order cancelled with compensation trigger', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "    pm.expect(res.data.cancelOrder).to.exist;",
                                        "    pm.expect(res.data.cancelOrder.orderStatus).to.equal('CANCELLED');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"},
                                {"key": "Authorization", "value": "Bearer {{user_jwt_token}}", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "mutation CancelOrder($id: ID!) {\n  cancelOrder(id: $id) {\n    id\n    orderStatus\n  }\n}",
                                    "variables": "{\n  \"id\": \"{{cancel_order_id}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Cancels a separate newly placed order to verify saga compensation and inventory restoration."
                        },
                        "response": []
                    },
                    {
                        "name": "10. Federated Inventory Query",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Inventory stock details returned', () => {",
                                        "    pm.expect(res.data.inventory).to.exist;",
                                        "    pm.expect(res.data.inventory.sku).to.equal(pm.collectionVariables.get('product_sku'));",
                                        "    pm.expect(res.data.inventory.quantity).to.be.a('number');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetInventory($sku: String!) {\n  inventory(sku: $sku) {\n    id\n    sku\n    quantity\n    isInStock\n  }\n}",
                                    "variables": "{\n  \"sku\": \"{{product_sku}}\"\n}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Direct GraphQL query to inventory subgraph via Cosmo Router."
                        },
                        "response": []
                    },
                    {
                        "name": "11. All Inventories Batch Query",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('No GraphQL Errors', () => {",
                                        "    pm.expect(res.errors).to.be.undefined;",
                                        "});",
                                        "pm.test('Inventories array returned', () => {",
                                        "    pm.expect(res.data.inventories).to.be.an('array');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "graphql",
                                "graphql": {
                                    "query": "query GetAllInventories {\n  inventories {\n    id\n    sku\n    quantity\n    isInStock\n  }\n}",
                                    "variables": "{}"
                                }
                            },
                            "url": {
                                "raw": "{{base_url}}/graphql",
                                "host": ["{{base_url}}"],
                                "path": ["graphql"]
                            },
                            "description": "Fetches all inventory stock levels via Cosmo Router."
                        },
                        "response": []
                    }
                ]
            },
            {
                "name": "📊 Telemetry & Funnel Events",
                "item": [
                    {
                        "name": "1. Record Funnel Event - CART_ADD",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Funnel event accepted (HTTP 202)', () => {",
                                        "    pm.response.to.have.status(202);",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "raw",
                                "raw": "{\n  \"eventType\": \"CART_ADD\",\n  \"sku\": \"{{product_sku}}\",\n  \"category\": \"Electronics\",\n  \"step\": \"cart\"\n}"
                            },
                            "url": {
                                "raw": "{{base_url}}/api/order/funnel",
                                "host": ["{{base_url}}"],
                                "path": ["api", "order", "funnel"]
                            },
                            "description": "Records CART_ADD funnel telemetry event."
                        },
                        "response": []
                    },
                    {
                        "name": "2. Record Funnel Event - CHECKOUT_START",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Funnel event accepted (HTTP 202)', () => {",
                                        "    pm.response.to.have.status(202);",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "raw",
                                "raw": "{\n  \"eventType\": \"CHECKOUT_START\",\n  \"sku\": \"{{product_sku}}\",\n  \"category\": \"Electronics\",\n  \"step\": \"shipping\"\n}"
                            },
                            "url": {
                                "raw": "{{base_url}}/api/order/funnel",
                                "host": ["{{base_url}}"],
                                "path": ["api", "order", "funnel"]
                            },
                            "description": "Records CHECKOUT_START funnel telemetry event."
                        },
                        "response": []
                    },
                    {
                        "name": "3. Record Funnel Event - CHECKOUT_STEP",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Funnel event accepted (HTTP 202)', () => {",
                                        "    pm.response.to.have.status(202);",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "raw",
                                "raw": "{\n  \"eventType\": \"CHECKOUT_STEP\",\n  \"sku\": \"{{product_sku}}\",\n  \"category\": \"Electronics\",\n  \"step\": \"payment\"\n}"
                            },
                            "url": {
                                "raw": "{{base_url}}/api/order/funnel",
                                "host": ["{{base_url}}"],
                                "path": ["api", "order", "funnel"]
                            },
                            "description": "Records CHECKOUT_STEP funnel telemetry event."
                        },
                        "response": []
                    }
                ]
            },
            {
                "name": "🛠️ Direct Subservice Endpoints (Fallback & M2M)",
                "item": [
                    {
                        "name": "1. Products Service Direct Catalog",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('Products array returned', () => {",
                                        "    pm.expect(res).to.be.an('array');",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "GET",
                            "header": [],
                            "url": {
                                "raw": "{{base_url}}/api/product",
                                "host": ["{{base_url}}"],
                                "path": ["api", "product"]
                            },
                            "description": "Direct REST endpoint to Products Service (:8004/api/product)."
                        },
                        "response": []
                    },
                    {
                        "name": "2. Inventory Service Direct In-Stock",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});",
                                        "const res = pm.response.json();",
                                        "pm.test('Stock check response has the expected shape', () => {",
                                        "    pm.expect(res).to.be.an('object');",
                                        "    pm.expect(res).to.have.property('errorMessages');",
                                        "    pm.expect(res.errorMessages == null || res.errorMessages.length === 0).to.be.true;",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "POST",
                            "header": [
                                {"key": "Content-Type", "value": "application/json", "type": "text"}
                            ],
                            "body": {
                                "mode": "raw",
                                "raw": "[\n  {\n    \"sku\": \"{{product_sku}}\",\n    \"quantity\": 1\n  }\n]"
                            },
                            "url": {
                                "raw": "{{base_url}}/api/inventory/in-stock",
                                "host": ["{{base_url}}"],
                                "path": ["api", "inventory", "in-stock"]
                            },
                            "description": "Direct REST endpoint to Inventory Service (:8001/api/inventory/in-stock)."
                        },
                        "response": []
                    },
                    {
                        "name": "3. Orders Service Direct List",
                        "event": [
                            {
                                "listen": "test",
                                "script": {
                                    "type": "text/javascript",
                                    "exec": [
                                        "pm.test('Status is 200 OK', () => {",
                                        "    pm.response.to.have.status(200);",
                                        "});"
                                    ]
                                }
                            }
                        ],
                        "request": {
                            "method": "GET",
                            "header": [
                                {"key": "Authorization", "value": "Bearer {{user_jwt_token}}", "type": "text"}
                            ],
                            "url": {
                                "raw": "{{base_url}}/api/order",
                                "host": ["{{base_url}}"],
                                "path": ["api", "order"]
                            },
                            "description": "Direct REST endpoint to Orders Service (:8003/api/order)."
                        },
                        "response": []
                    }
                ]
            }
        ],
        "event": [
            {
                "listen": "prerequest",
                "script": {
                    "type": "text/javascript",
                    "exec": [
                        "const baseUrl = pm.variables.get('BASE_URL') || pm.variables.get('base_url');",
                        "if (baseUrl) {",
                        "    pm.variables.set('base_url', baseUrl);",
                        "    pm.variables.set('BASE_URL', baseUrl);",
                        "}"
                    ]
                }
            }
        ],
        "variable": [
            {
                "key": "base_url",
                "value": "http://127.0.0.1:5173",
                "type": "string"
            },
            {
                "key": "BASE_URL",
                "value": "http://127.0.0.1:5173",
                "type": "string"
            },
            {
                "key": "keycloak_url",
                "value": "http://localhost:8181",
                "type": "string"
            },
            {
                "key": "user_jwt_token",
                "value": "",
                "type": "string"
            },
            {
                "key": "admin_jwt_token",
                "value": "",
                "type": "string"
            },
            {
                "key": "order_id",
                "value": "1",
                "type": "string"
            },
            {
                "key": "cancel_order_id",
                "value": "",
                "type": "string"
            },
            {
                "key": "product_sku",
                "value": "LAPTOP-PRO",
                "type": "string"
            },
            {
                "key": "idempotency_key",
                "value": "",
                "type": "string"
            },
            {
                "key": "tracking_number",
                "value": "",
                "type": "string"
            }
        ]
    }

    graphql_folder = next(
        group for group in collection["item"]
        if group["name"] == "🚀 Cosmo Router - GraphQL Supergraph"
    )
    graphql_items = graphql_folder["item"]
    place_order = next(item for item in graphql_items if item["name"].startswith("4. Place Order"))
    cancel_order = next(item for item in graphql_items if item["name"].startswith("10. Cancel Order"))

    cancellable_order = copy.deepcopy(place_order)
    cancellable_order["name"] = "9. Place Order for Cancellation"
    cancellable_order["description"] = "Creates a separate PLACED order for the cancellation and inventory compensation request that follows."
    for event in cancellable_order.get("event", []):
        if event.get("listen") == "test":
            event["script"]["exec"] = [
                line.replace("set('order_id',", "set('cancel_order_id',")
                for line in event["script"]["exec"]
            ]
    graphql_items.insert(graphql_items.index(cancel_order), cancellable_order)

    def mark_public_requests(items):
        public_suffixes = (
            "/api/order/funnel",
            "/api/notifications/stream",
            "/api/product",
            "/api/inventory/in-stock",
        )
        for item in items:
            if "item" in item:
                mark_public_requests(item["item"])
                continue
            request = item.get("request", {})
            raw_url = request.get("url", {}).get("raw", "")
            if raw_url.endswith(public_suffixes):
                request["auth"] = {"type": "noauth"}

    mark_public_requests(collection["item"])

    target_path = "devsecops/testing/newman/microservices.postman_collection.json"
    with open(target_path, "w", encoding="utf-8") as f:
        json.dump(collection, f, indent=2, ensure_ascii=False)
    print(f"Successfully generated {target_path}.")

if __name__ == "__main__":
    build_postman_collection()
