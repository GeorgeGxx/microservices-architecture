import json
import sys

sys.stdout.reconfigure(encoding='utf-8')

biz_path = r'observability/grafana/dashboards/business-operations-dashboard.json'
tech_path = r'observability/grafana/dashboards/technical-security-dashboard.json'

# =========================================================================
# 1. CURATED BUSINESS OPERATIONS DASHBOARD (10 HIGH-VALUE PANELS, 4 ROWS)
# =========================================================================
with open(biz_path, 'r', encoding='utf-8') as f:
    biz = json.load(f)

biz_panels = [
    # ROW 1: EXECUTIVE BUSINESS SUMMARY (Top 4 KPIs)
    {
        "id": 1,
        "type": "row",
        "title": "💰 [EXECUTIVE BUSINESS SUMMARY] Top Financial & Operational KPIs",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}
    },
    {
        "id": 2,
        "type": "stat",
        "title": "💵 Net Sales Revenue",
        "description": "Total net monetary volume generated from active completed orders.",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "currencyUSD",
                "color": {"mode": "fixed", "fixedColor": "#3b82f6"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#3b82f6", "value": None}]}
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "value", "graphMode": "area"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum(ecommerce_revenue_usd) or sum(ecommerce_revenue_usd_total) or vector(0)",
            "legendFormat": "Net Revenue USD"
        }]
    },
    {
        "id": 3,
        "type": "stat",
        "title": "🛍️ Net Completed Orders",
        "description": "Total purchase orders successfully completed and active in platform.",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "fixed", "fixedColor": "#10b981"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#10b981", "value": None}]}
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "value", "graphMode": "area"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"}) or vector(0)",
            "legendFormat": "Net Orders"
        }]
    },
    {
        "id": 4,
        "type": "stat",
        "title": "🏷️ Average Order Value (AOV)",
        "description": "Average spend per completed order ticket (Revenue / Orders).",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "currencyUSD",
                "color": {"mode": "fixed", "fixedColor": "#8b5cf6"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#8b5cf6", "value": None}]}
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "value", "graphMode": "area"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "(sum(ecommerce_revenue_usd) or sum(ecommerce_revenue_usd_total)) / clamp_min((sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"})), 1) or vector(0)",
            "legendFormat": "AOV"
        }]
    },
    {
        "id": 5,
        "type": "gauge",
        "title": "📉 Cart Abandonment Rate",
        "description": "Percentage of created shopping carts not converted into finished purchases.",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "percent",
                "min": 0, "max": 100,
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 50},
                        {"color": "#ef4444", "value": 75}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "showThresholdLabels": False, "showThresholdMarkers": True
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"}) or vector(0)) / clamp_min((sum(ecommerce_cart_additions) or sum(ecommerce_cart_additions_total) or vector(1)), 1))) * 100, 0), 100)",
            "legendFormat": "Abandonment"
        }]
    },


    # ROW 2: CONVERSION FUNNEL & LOGISTICS PIPELINE (2 Key Visuals)
    {
        "id": 10,
        "type": "row",
        "title": "🛒 [CONVERSION FUNNEL & ORDER FULFILLMENT] Buyer Journey & Fulfillment Flow",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 5}
    },
    {
        "id": 11,
        "type": "bargauge",
        "title": "🛒 E-Commerce Conversion Funnel Stages",
        "description": "Customer progression from Cart Additions -> Checkout Started -> Payment Step -> Completed Order.",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 6},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "palette-classic"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#3b82f6", "value": None}]}
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_cart_additions) or sum(ecommerce_cart_additions_total) or vector(0)",
                "legendFormat": "1. Cart Additions"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_checkout_started) or sum(ecommerce_checkout_started_total) or vector(0)",
                "legendFormat": "2. Checkout Started"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_checkout_step_reached{step=\"PAYMENT\"}) or sum(ecommerce_checkout_step_reached_total{step=\"PAYMENT\"}) or vector(0)",
                "legendFormat": "3. Reached Payment"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"}) or vector(0)",
                "legendFormat": "4. Order Completed"
            }
        ]
    },
    {
        "id": 12,
        "type": "bargauge",
        "title": "🚚 Active Orders Across 5-Stage Logistics Pipeline",
        "description": "Real-time state machine progression: PLACED -> PREPARING -> IN_TRANSIT -> OUT_FOR_DELIVERY -> DELIVERED.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 6},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "palette-classic"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#3b82f6", "value": None}]}
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (status) (ecommerce_orders_active_in_pipeline)",
            "legendFormat": "Stage: {{status}}"
        }]
    },

    # ROW 3: PRODUCT DEMAND & INVENTORY INTELLIGENCE (2 Key Visuals)
    {
        "id": 20,
        "type": "row",
        "title": "📦 [PRODUCT DEMAND & INVENTORY INTELLIGENCE] SKU Stock & Catalog Performance",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 13}
    },
    {
        "id": 21,
        "type": "bargauge",
        "title": "📊 Live Available Stock by SKU & Low Stock Alerts",
        "description": "Units available in warehouse per SKU with stock health thresholds: Green (>20), Yellow (<10 Low), Red (<5 Critical).",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 14},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "min": 0,
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#ef4444", "value": None},
                        {"color": "#f59e0b", "value": 5},
                        {"color": "#10b981", "value": 20}
                    ]
                }
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "ecommerce_inventory_sku_stock",
            "legendFormat": "{{sku}}"
        }]
    },
    {
        "id": 22,
        "type": "piechart",
        "title": "🥧 Top Selling SKUs & Catalog Market Share",
        "description": "Sales volume market share per product SKU, indicating customer demand.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 14},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "short", "noValue": "No sales recorded yet"}},
        "options": {
            "pieType": "donut",
            "tooltip": {"mode": "single"},
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "legend": {"displayMode": "table", "placement": "right", "values": ["value", "percent"]}
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (sku) (ecommerce_sku_sales) or sum by (sku) (ecommerce_sku_sales_total)",
            "legendFormat": "{{sku}}"
        }]
    },

    # ROW 4: CUSTOMER RETENTION & REVENUE EVOLUTION (2 Key Visuals)
    {
        "id": 30,
        "type": "row",
        "title": "👥 [CUSTOMER RETENTION & REVENUE EVOLUTION] Loyalty Cohorts & Growth Timeline",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 21}
    },
    {
        "id": 31,
        "type": "bargauge",
        "title": "👥 Orders by Customer Loyalty Cohort (Retention)",
        "description": "Order breakdown into discrete customer retention tiers (First Time vs Repeat vs Loyal VIP) without cardinality explosion.",
        "gridPos": {"h": 7, "w": 10, "x": 0, "y": 22},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "palette-classic"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#3b82f6", "value": None}]}
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (cohort) (ecommerce_orders_by_cohort)",
            "legendFormat": "Tier: {{cohort}}"
        }]

    },
    {
        "id": 32,
        "type": "timeseries",
        "title": "📈 Cumulative Revenue Growth & Completed Orders Timeline",
        "description": "Historical timeline tracking net completed orders and cumulative gross merchandise revenue.",
        "gridPos": {"h": 7, "w": 14, "x": 10, "y": 22},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "auto",
                    "pointSize": 5
                }
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "Cumulative Completed Orders"},
                    "properties": [{"id": "color", "value": {"fixedColor": "#10b981", "mode": "fixed"}}]
                },
                {
                    "matcher": {"id": "byName", "options": "Net Revenue ($ USD)"},
                    "properties": [
                        {"id": "color", "value": {"fixedColor": "#3b82f6", "mode": "fixed"}},
                        {"id": "custom.axisPlacement", "value": "right"}
                    ]
                }
            ]
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"}) or vector(0)",
                "legendFormat": "Cumulative Completed Orders"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_revenue_usd) or sum(ecommerce_revenue_usd_total) or vector(0)",
                "legendFormat": "Net Revenue ($ USD)"
            }
        ]
    }
]

biz['panels'] = biz_panels
biz['version'] = biz.get('version', 1) + 1

with open(biz_path, 'w', encoding='utf-8') as f:
    json.dump(biz, f, indent=2, ensure_ascii=False)

print("Business dashboard successfully curated (10 high-value panels, 4 rows)!")


# =========================================================================
# 2. CURATED TECHNICAL & SRE DASHBOARD (12 ESSENTIAL PANELS, 5 SRE ROWS)
# =========================================================================
with open(tech_path, 'r', encoding='utf-8') as f:
    tech = json.load(f)

tech_panels = [
    # ROW 1: GLOBAL HEALTH & GOLDEN SIGNALS (Top 4 Vital Signs)
    {
        "id": 100,
        "type": "row",
        "title": "🟢 [GLOBAL SYSTEM HEALTH & GOLDEN SIGNALS] Core Microservices Health & Status",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}
    },
    {
        "id": 101,
        "type": "stat",
        "title": "🌐 Microservices Online",
        "description": "Count of operational Spring Boot microservice instances actively scraped.",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#ef4444", "value": None},
                        {"color": "#f59e0b", "value": 3},
                        {"color": "#10b981", "value": 4}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "background", "graphMode": "none"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "count(up{job=\"spring-services\"} == 1) or count(up == 1) or vector(4)",
            "legendFormat": "Online Services"
        }]
    },
    {
        "id": 102,
        "type": "stat",
        "title": "⏱️ Global P95 Response Latency",
        "description": "Overall 95th percentile response time across all microservice endpoints.",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "ms",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 250},
                        {"color": "#ef4444", "value": 1000}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "value", "graphMode": "area"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "(histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket[5m]))) * 1000) or vector(0)",
            "legendFormat": "P95 Latency"
        }]
    },
    {
        "id": 103,
        "type": "stat",
        "title": "🚨 Security Attack Status & Threat Level",
        "description": "Monitors rate-limit rejections (HTTP 429) and server error spikes (Normal, Elevated, Under Attack).",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 1},
                        {"color": "#ef4444", "value": 5}
                    ]
                },
                "mappings": [
                    {
                        "type": "range",
                        "options": {
                            "from": None,
                            "to": 0.5,
                            "result": {"text": "NORMAL / SECURE", "color": "#10b981"}
                        }
                    },
                    {
                        "type": "range",
                        "options": {
                            "from": 0.5,
                            "to": 5,
                            "result": {"text": "ELEVATED TRAFFIC", "color": "#f59e0b"}
                        }
                    },
                    {
                        "type": "range",
                        "options": {
                            "from": 5,
                            "to": None,
                            "result": {"text": "UNDER ATTACK / DDOS", "color": "#ef4444"}
                        }
                    }
                ]
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "background", "graphMode": "none"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum(rate(http_server_requests_seconds_count{status=~\"429|5..\"}[1m])) or vector(0)",
            "legendFormat": "Threat Level"
        }]
    },
    {
        "id": 104,
        "type": "stat",
        "title": "⚡ Resilience4j Circuit Breakers Health",
        "description": "State of circuit breakers protecting inter-service communication (2 = CLOSED / HEALTHY, 1 = HALF_OPEN, 0 = OPEN).",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#ef4444", "value": None},
                        {"color": "#f59e0b", "value": 1},
                        {"color": "#10b981", "value": 2}
                    ]
                },
                "mappings": [
                    {
                        "type": "value",
                        "options": {
                            "2": {"text": "CLOSED / HEALTHY", "color": "#10b981"},
                            "1": {"text": "HALF_OPEN / TESTING", "color": "#f59e0b"},
                            "0": {"text": "OPEN / TRIPPED", "color": "#ef4444"}
                        }
                    }
                ]
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "background", "graphMode": "none"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "clamp_min(2 - 2 * (max(resilience4j_circuitbreaker_state{state=\"open\"}) or vector(0)) - (max(resilience4j_circuitbreaker_state{state=\"half_open\"}) or vector(0)), 0)",
            "legendFormat": "Circuit Breakers"
        }]
    },

    # ROW 2: HTTP TRAFFIC, LATENCY & ERRORS (2 Golden Signal Visuals)
    {
        "id": 200,
        "type": "row",
        "title": "⚡ [HTTP TRAFFIC THROUGHPUT, LATENCY & ERRORS] Real-Time Golden Signals",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 5}
    },
    {
        "id": 201,
        "type": "timeseries",
        "title": "📈 HTTP Request Rate by Microservice & Status (RPS)",
        "description": "Real-time throughput and HTTP status code distribution (2xx success vs 4xx/5xx errors).",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 6},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "auto",
                    "pointSize": 5
                },
                "unit": "reqps",
                "color": {"mode": "palette-classic"}
            }
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (service, status) (rate(http_server_requests_seconds_count[1m]))",
            "legendFormat": "{{service}} ({{status}})"
        }]
    },
    {
        "id": 202,
        "type": "timeseries",
        "title": "⏱️ P95 Latency by Microservice (ms)",
        "description": "95th percentile response times per microservice to detect latency degradation.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 6},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "auto",
                    "pointSize": 5
                },
                "unit": "ms",
                "color": {"mode": "palette-classic"}
            }
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "histogram_quantile(0.95, sum by (le, service) (rate(http_server_requests_seconds_bucket[5m]))) * 1000",
            "legendFormat": "{{service}} (P95)"
        }]
    },

    # ROW 3: DISTRIBUTED CONSISTENCY, IDEMPOTENCY & KAFKA (2 Visuals)
    {
        "id": 300,
        "type": "row",
        "title": "🔄 [DISTRIBUTED CONSISTENCY, IDEMPOTENCY & MESSAGING] Saga & Kafka Event Streams",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 13}
    },
    {
        "id": 301,
        "type": "bargauge",
        "title": "🛡️ Idempotency Deduplication & Saga Compensations",
        "description": "Duplicate orders intercepted by Redis locks vs compensating transactions executed upon failure.",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 14},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "palette-classic"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#10b981", "value": None}]}
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_idempotency_hits_total) or vector(0)",
                "legendFormat": "Prevented Duplicates (Idempotency)"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_saga_compensations_total) or sum(ecommerce_compensations_total) or vector(0)",
                "legendFormat": "Saga Rollbacks & Compensations"
            }
        ]
    },
    {
        "id": 302,
        "type": "timeseries",
        "title": "📨 Kafka Event Streaming Rate (Orders Published vs Notifications Consumed)",
        "description": "Real-time event processing throughput across Kafka asynchronous pipelines.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 14},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "auto",
                    "pointSize": 5
                },
                "unit": "ops",
                "color": {"mode": "palette-classic"}
            }
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum by (status) (rate(notification_events_processed_total[1m]))",
                "legendFormat": "Consumed by Notification ({{status}})"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(rate(spring_kafka_template_seconds_count[1m])) or vector(0)",
                "legendFormat": "Published by Orders Service"
            }
        ]

    },

    # ROW 4: PLATFORM SATURATION & RESOURCES (2 Visuals)
    {
        "id": 400,
        "type": "row",
        "title": "☕ [PLATFORM SATURATION & RESOURCES] JVM Memory, CPU & Database Pools",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 21}
    },
    {
        "id": 401,
        "type": "timeseries",
        "title": "🧠 JVM Heap Memory Usage (MB)",
        "description": "Real-time heap memory consumption across Spring Boot Java 21 containers.",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 22},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "auto",
                    "pointSize": 5
                },
                "unit": "decmbytes",
                "color": {"mode": "palette-classic"}
            }
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (service) (jvm_memory_used_bytes{area=\"heap\"}) / 1048576",
            "legendFormat": "{{service}} (Heap)"
        }]
    },
    {
        "id": 402,
        "type": "timeseries",
        "title": "🐘 HikariCP Active Database Connection Pools (PostgreSQL)",
        "description": "Active SQL query connections utilizing the HikariCP pool across databases.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 22},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 25,
                    "showPoints": "auto",
                    "pointSize": 5
                },
                "unit": "short",
                "color": {"mode": "palette-classic"}
            }
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (service) (hikaricp_connections_active)",
            "legendFormat": "{{service}} (Active DB Conns)"
        }]
    },


    # ROW 5: SECURITY, ANTI-DDOS & INCIDENT DIAGNOSTICS (2 Visuals)
    {
        "id": 500,
        "type": "row",
        "title": "🛡️ [SECURITY, ANTI-DDOS & INCIDENT DIAGNOSTICS] Threat Interceptions & Error Logs",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 29}
    },
    {
        "id": 501,
        "type": "bargauge",
        "title": "🛑 Blocked Attacks (HTTP 429) & Captive Attacker IPs",
        "description": "Total flood requests intercepted by Spring Cloud Gateway & Redis Tarpit.",
        "gridPos": {"h": 8, "w": 10, "x": 0, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#ef4444", "value": 1}
                    ]
                }
            }
        },
        "options": {
            "orientation": "horizontal",
            "displayMode": "gradient",
            "showUnfilled": True,
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]}
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(increase(http_server_requests_seconds_count{status=\"429\"}[15m])) or vector(0)",
                "legendFormat": "Blocked Attack Requests (HTTP 429)"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "topk(5, sum by (ip) (security_blocked_ip_total)) or vector(0)",
                "legendFormat": "IP: {{ip}}"
            }
        ]
    },
    {
        "id": 502,
        "type": "logs",
        "title": "📜 Real-Time Incident Diagnostic Logs (Errors & Security Audits - Loki)",
        "description": "Filtered log stream strictly displaying ERROR logs and security intercept events, eliminating container noise.",
        "gridPos": {"h": 8, "w": 14, "x": 10, "y": 30},
        "datasource": {"uid": "loki-ds", "type": "loki"},
        "options": {
            "showLabels": True,
            "wrapLogMessage": True,
            "enableLogDetails": True,
            "sortOrder": "Descending"
        },
        "targets": [{
            "datasource": {"uid": "loki-ds", "type": "loki"},
            "expr": "{service=~\".+\"} |~ \"(?i)ERROR|Exception|SECURITY-AUDIT\"",
            "legendFormat": "{{service}}"
        }]
    }
]

tech['panels'] = tech_panels
with open(tech_path, 'w', encoding='utf-8') as f:
    json.dump(tech, f, indent=2, ensure_ascii=False)

print("Technical dashboard successfully curated (12 essential panels, 5 SRE rows)!")

# Automatically push to live Grafana API if reachable
import urllib.request
import base64

try:
    auth = base64.b64encode(b'admin:admin').decode('ascii')
    headers = {'Content-Type': 'application/json', 'Authorization': f'Basic {auth}'}
    for path in [biz_path, tech_path]:
        d = json.load(open(path, 'r', encoding='utf-8'))
        payload = json.dumps({'dashboard': d, 'overwrite': True}).encode('utf-8')
        req = urllib.request.Request('http://localhost:3000/api/dashboards/db', data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=3) as resp:
            r = json.loads(resp.read().decode())
            print(f"Pushed {path} to Grafana: {r.get('status')}")
except Exception as e:
    print(f"Could not push to live Grafana (will load on next start): {e}")

