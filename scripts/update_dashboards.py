import json
import argparse
import base64
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

biz_path = r'observability/grafana/dashboards/business-operations-dashboard.json'
tech_path = r'observability/grafana/dashboards/technical-security-dashboard.json'

# =========================================================================
def build_business_dashboard():
    with open(biz_path, 'r', encoding='utf-8') as f:
        biz = json.load(f)

    for variable in biz.get("templating", {}).get("list", []):
        if variable.get("name") == "service":
            biz_service_query = 'label_values(up{service=~"orders-service|inventory-service|products-service|analytics-service|payments-service|fulfillment-service"}, service)'
            variable["definition"] = biz_service_query
            variable.setdefault("query", {})["query"] = biz_service_query

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
            "expr": "((sum(ecommerce_funnel_events_total{event_type=\"cart_add\"}) or sum(ecommerce_cart_additions) or sum(ecommerce_cart_additions_total) or vector(0)) > bool 0) * clamp_max(clamp_min((1 - ((sum(ecommerce_orders{status=\"COMPLETED\"}) or sum(ecommerce_orders_total{status=\"COMPLETED\"}) or vector(0)) / clamp_min((sum(ecommerce_funnel_events_total{event_type=\"cart_add\"}) or sum(ecommerce_cart_additions) or sum(ecommerce_cart_additions_total)), 1))) * 100, 0), 100) or vector(0)",
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
                "expr": "sum(ecommerce_funnel_events_total{event_type=\"cart_add\"}) or sum(ecommerce_cart_additions) or sum(ecommerce_cart_additions_total) or vector(0)",
                "legendFormat": "1. Cart Additions"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_funnel_events_total{event_type=\"checkout_start\"}) or sum(ecommerce_checkout_started) or sum(ecommerce_checkout_started_total) or vector(0)",
                "legendFormat": "2. Checkout Started"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "sum(ecommerce_funnel_events_total{event_type=\"checkout_step\",step=\"PAYMENT\"}) or sum(ecommerce_checkout_step_reached{step=\"PAYMENT\"}) or sum(ecommerce_checkout_step_reached_total{step=\"PAYMENT\"}) or vector(0)",
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
            "expr": "sum by (status) (ecommerce_orders_active_in_pipeline) or vector(0)",
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
            "expr": "sum by (sku) (ecommerce_sku_sales) or sum by (sku) (ecommerce_sku_sales_total) or vector(0)",
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
            "expr": "sum by (cohort) (ecommerce_orders_by_cohort) or vector(0)",
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
    },
    {
        "id": 40,
        "type": "row",
        "title": "🔮 [DEMAND FORECAST READINESS & MODEL QUALITY] Forecast Data for Inventory Decisions",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 29}
    },
    {
        "id": 41,
        "type": "stat",
        "title": "🕒 Age of Latest Successful Forecast",
        "description": "Elapsed time since the forecast API last returned a successful forecast. No data means no successful forecast has been recorded yet or telemetry is unavailable.",
        "gridPos": {"h": 4, "w": 4, "x": 0, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "h", "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "#10b981", "value": None}, {"color": "#f59e0b", "value": 24}, {"color": "#ef4444", "value": 72}]}}},
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "value", "graphMode": "area", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "((time() - max(demand_forecast_last_success_unixtime{service=\"demand-forecast-service\"})) / 3600) and (max(demand_forecast_last_success_unixtime{service=\"demand-forecast-service\"}) > 0) or vector(0)", "legendFormat": "Forecast age"}]
    },
    {
        "id": 42,
        "type": "stat",
        "title": "🗓️ Age of Latest Sales Data",
        "description": "Age of the newest sales date included in forecast input data. A stale source can make current forecasts less useful for replenishment decisions.",
        "gridPos": {"h": 4, "w": 4, "x": 4, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "d", "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "#10b981", "value": None}, {"color": "#f59e0b", "value": 2}, {"color": "#ef4444", "value": 7}]}}},
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "value", "graphMode": "area", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "((time() - max(demand_forecast_last_observed_sale_unixtime{service=\"demand-forecast-service\"})) / 86400) and (max(demand_forecast_last_observed_sale_unixtime{service=\"demand-forecast-service\"}) > 0) or vector(0)", "legendFormat": "Sales data age"}]
    },
    {
        "id": 43,
        "type": "stat",
        "title": "🧠 Age of Active Forecast Model",
        "description": "Time since the active demand model was trained. Review this with sales-data freshness and model error before relying on forecasts.",
        "gridPos": {"h": 4, "w": 4, "x": 8, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "h", "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "#10b981", "value": None}, {"color": "#f59e0b", "value": 24}, {"color": "#ef4444", "value": 48}]}}},
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "value", "graphMode": "area", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "(max(demand_forecast_model_age_seconds{service=\"demand-forecast-service\"}) / 3600) and (max(demand_forecast_model_age_seconds{service=\"demand-forecast-service\"}) > 0) or vector(0)", "legendFormat": "Model age"}]
    },
    {
        "id": 44,
        "type": "stat",
        "title": "📏 Active Model RMSE",
        "description": "Root mean squared forecast error for the active model, in the target's units (not a percentage). Lower is better; compare with an agreed inventory-planning tolerance.",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "palette-classic"}}},
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "value", "graphMode": "none", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "(max(demand_forecast_model_rmse{service=\"demand-forecast-service\"}) and (max(demand_forecast_model_age_seconds{service=\"demand-forecast-service\"}) > 0)) or vector(0)", "legendFormat": "RMSE"}]
    },
    {
        "id": 45,
        "type": "stat",
        "title": "📏 Active Model MAE",
        "description": "Mean absolute forecast error for the active model, in the target's units (not a percentage). Lower is better; compare with an agreed inventory-planning tolerance.",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 30},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {"defaults": {"unit": "short", "color": {"mode": "palette-classic"}}},
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "value", "graphMode": "none", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "(max(demand_forecast_model_mae{service=\"demand-forecast-service\"}) and (max(demand_forecast_model_age_seconds{service=\"demand-forecast-service\"}) > 0)) or vector(0)", "legendFormat": "MAE"}]
    }
]

    if biz.get('panels') != biz_panels:
        biz['version'] = biz.get('version', 1) + 1
    biz['panels'] = biz_panels

    with open(biz_path, 'w', encoding='utf-8') as f:
        json.dump(biz, f, indent=2, ensure_ascii=False)

    print("Business dashboard successfully curated (15 high-value panels, 5 rows)!")


def build_technical_dashboard():
    with open(tech_path, 'r', encoding='utf-8') as f:
        tech = json.load(f)

    # Keep the technical service filter in sync with the SRE request panels.
    for variable in tech.get("templating", {}).get("list", []):
        if variable.get("name") == "service":
            service_query = 'label_values(up{service=~"cosmo-router|orders-service|products-service|inventory-service|notification-service|payments-service|fulfillment-service|analytics-service|demand-forecast-service"}, service)'
            variable["definition"] = service_query
            variable.setdefault("query", {})["query"] = service_query

    tech_panels = [
    # ROW 1: GLOBAL HEALTH & GOLDEN SIGNALS (Top 6 Vital Signs)
    {
        "id": 100,
        "type": "row",
        "title": "🟢 [GLOBAL SYSTEM HEALTH & GOLDEN SIGNALS] Application & Forecast Service Health",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 0}
    },
    {
        "id": 101,
        "type": "stat",
        "title": "🌐 Core Microservices Online",
        "description": "Count of unique operational core business microservices active (Cosmo Router, Products, Orders, Inventory, Notifications, Payments, Fulfillment, Analytics) independent of pod replica scaling.",
        "gridPos": {"h": 4, "w": 4, "x": 0, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#ef4444", "value": None},
                        {"color": "#f59e0b", "value": 6},
                        {"color": "#10b981", "value": 8}
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
            "expr": "count(count by (service) (up{service=~\"cosmo-router|orders-service|products-service|inventory-service|notification-service|payments-service|fulfillment-service|analytics-service\"} == 1)) or vector(8)",
            "legendFormat": "Active Business Roles"
        }]
    },
    {
        "id": 102,
        "type": "stat",
        "title": "⏱️ Global P95 Response Latency",
        "description": "Overall 95th percentile response time across all microservice endpoints.",
        "gridPos": {"h": 4, "w": 4, "x": 4, "y": 1},
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
            "expr": "(histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket[5m]))) * 1000) or histogram_quantile(0.95, sum by (le) (rate(router_http_request_duration_milliseconds_bucket{wg_subgraph_name=\"\"}[5m]))) or vector(0)",
            "legendFormat": "P95 Latency"
        }]
    },
    {
        "id": 103,
        "type": "stat",
        "title": "🚨 Edge Security Attack Status & Threat Level",
        "description": "Count of actual HTTP 429 responses logged by frontend Nginx. Green: <1/sec, amber: 1–5/sec, red: ≥5/sec. The value is a rolling one-minute rate and returns to green after traffic stops.",
        "gridPos": {"h": 4, "w": 4, "x": 8, "y": 1},
        "datasource": {"uid": "loki-ds", "type": "loki"},
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
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "background", "graphMode": "none"
        },
        "targets": [{
            "datasource": {"uid": "loki-ds", "type": "loki"},
          "expr": "sum(rate({service=\"frontend\"} | json | __error__=\"\" | status=\"429\" [1m])) or vector(0)",
            "legendFormat": "Frontend HTTP 429 / second",
            "queryType": "range"
        }]
    },
    {
        "id": 104,
        "type": "stat",
        "title": "⚡ Resilience4j Circuit Breakers Health",
        "description": "State of circuit breakers protecting inter-service communication (2 = CLOSED / HEALTHY, 1 = HALF_OPEN, 0 = OPEN).",
        "gridPos": {"h": 4, "w": 4, "x": 12, "y": 1},
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
    {
        "id": 105,
        "type": "stat",
        "title": "🎯 Availability SLO Burn (Worst Service)",
        "description": "Single value showing the highest 5-minute 5xx ratio divided by the 0.5% error budget across the core services and demand forecast API. Health checks are excluded from the forecast API ratio. Red starts at the 14.4x multi-window alert threshold.",
        "gridPos": {"h": 4, "w": 4, "x": 16, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "decimals": 2,
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 1},
                        {"color": "#ef4444", "value": 14.4}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "textMode": "value", "colorMode": "background", "graphMode": "none", "noValue": "No data"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "max((microservices:http_error_ratio:rate5m / 0.005) or on(service) (max by (service) (up{service=~\"products-service|inventory-service|orders-service|notification-service\"} == 1) * 0) or ((sum by (service) (rate(demand_forecast_http_requests_total{service=\"demand-forecast-service\",path!=\"/health\",status=~\"5..\"}[5m])) or on (service) (max by (service) (up{service=\"demand-forecast-service\"} == 1) * 0)) / clamp_min(sum by (service) (rate(demand_forecast_http_requests_total{service=\"demand-forecast-service\",path!=\"/health\"}[5m])), 1e-9) / 0.005))",
            "legendFormat": "Worst service (x budget burn)"
        }]
    },
    {
        "id": 106,
        "type": "stat",
        "title": "🔮 Forecast API Availability",
        "description": "Prometheus scrape health for the demand forecast API: UP means its metrics endpoint is reachable; DOWN or No data means forecasting telemetry is unavailable.",
        "gridPos": {"h": 4, "w": 4, "x": 20, "y": 1},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "min": 0,
                "max": 1,
                "color": {"mode": "thresholds"},
                "thresholds": {"mode": "absolute", "steps": [{"color": "#ef4444", "value": None}, {"color": "#10b981", "value": 1}]},
                "mappings": [{"type": "value", "options": {"0": {"text": "DOWN", "color": "#ef4444"}, "1": {"text": "UP", "color": "#10b981"}}}]
            }
        },
        "options": {"reduceOptions": {"values": False, "calcs": ["lastNotNull"]}, "textMode": "value", "colorMode": "background", "graphMode": "none", "noValue": "No data"},
        "targets": [{"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "max(up{service=\"demand-forecast-service\"}) or vector(0)", "legendFormat": "Forecast API"}]
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
        "description": "Real-time throughput and HTTP status code distribution (2xx success vs 4xx/5xx errors), including demand forecast API traffic when selected.",
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
            "expr": "sum by (service, status) (rate(http_server_requests_seconds_count{service=~\"$service\"}[1m])) or sum by (service, http_status_code) (rate(router_http_requests_total{service=~\"$service\",wg_subgraph_name=\"\"}[1m])) or sum by (service, status) (rate(demand_forecast_http_requests_total{service=~\"$service\",path!=\"/health\"}[1m]))",
            "legendFormat": "{{service}} ({{status}}{{http_status_code}})"
        }]
    },
    {
        "id": 202,
        "type": "timeseries",
        "title": "⏱️ P95 Latency by Microservice (ms)",
        "description": "95th percentile response times per microservice to detect latency degradation. Forecast API health-check requests are excluded.",
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
            "expr": "(histogram_quantile(0.95, sum by (le, service) (rate(http_server_requests_seconds_bucket{service=~\"$service\"}[5m]))) * 1000) or histogram_quantile(0.95, sum by (le, service) (rate(router_http_request_duration_milliseconds_bucket{service=~\"$service\",wg_subgraph_name=\"\"}[5m]))) or (histogram_quantile(0.95, sum by (le, service) (rate(demand_forecast_http_request_duration_seconds_bucket{service=~\"$service\",path!=\"/health\"}[5m]))) * 1000)",
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
                "expr": "sum by (status) (rate(notification_events_processed_total[1m])) or vector(0)",
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
        "description": "Active, idle, and queued connections per HikariCP pool. Active can correctly remain at zero while the application is idle; compare it with idle and pending connections before diagnosing a scrape issue.",
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
            "expr": "sum by (service, pool) (hikaricp_connections_active)",
            "legendFormat": "{{service}} / {{pool}} active"
        }, {
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (service, pool) (hikaricp_connections_idle)",
            "legendFormat": "{{service}} / {{pool}} idle"
        }, {
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum by (service, pool) (hikaricp_connections_pending)",
            "legendFormat": "{{service}} / {{pool}} pending"
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
        "title": "🛑 Blocked Attacks (HTTP 429) & Observed Peer IPs",
        "description": "Counts actual frontend Nginx HTTP 429 responses and ranks the socket peer IPs Nginx observed. No rows means no blocked request in the selected time range. The limiter ignores caller-supplied X-Forwarded-For values; behind another proxy, the peer may be that proxy.",
        "gridPos": {"h": 8, "w": 10, "x": 0, "y": 30},
        "datasource": {"uid": "loki-ds", "type": "loki"},
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
                "datasource": {"uid": "loki-ds", "type": "loki"},
                "expr": "sum(count_over_time({service=\"frontend\"} | json | __error__=\"\" | status=\"429\" [15m])) or vector(0)",
                "legendFormat": "Blocked HTTP 429 (15m)",
                "queryType": "range"
            },
            {
                "datasource": {"uid": "loki-ds", "type": "loki"},
                "expr": "topk(5, sum by (peer_ip) (count_over_time({service=\"frontend\"} | json | __error__=\"\" | status=\"429\" | peer_ip!=\"\" [15m])))",
                "legendFormat": "IP {{peer_ip}}",
                "queryType": "range"
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
        }, {
            "datasource": {"uid": "loki-ds", "type": "loki"},
            "expr": "{service=\"frontend\"} | json | __error__=\"\" | status=\"429\"",
            "legendFormat": "frontend rate-limit block"
        }]
    },
    # ROW 6: TELEMETRY PIPELINE & LOG FORWARDING (Grafana Alloy Engine)
    {
        "id": 600,
        "type": "row",
        "title": "⚡ [TELEMETRY PIPELINE & LOG FORWARDING] Grafana Alloy Engine",
        "collapsed": False,
        "gridPos": {"h": 1, "w": 24, "x": 0, "y": 38}
    },
    {
        "id": 601,
        "type": "stat",
        "title": "⚡ Alloy Scrape Target Health",
        "description": "Prometheus scrape health for Alloy. A value of 1 means the metrics endpoint is reachable; 0 means scrapes are failing. No data means the target is missing.",
        "gridPos": {"h": 4, "w": 6, "x": 0, "y": 39},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#ef4444", "value": None},
                        {"color": "#10b981", "value": 1}
                    ]
                },
                "mappings": [
                    {"type": "value", "options": {"0": {"text": "DOWN", "color": "#ef4444"}, "1": {"text": "HEALTHY", "color": "#10b981"}}}
                ]
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "colorMode": "background",
            "graphMode": "none",
            "textMode": "value"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "min(up{job=\"alloy\"})",
            "legendFormat": "Controller Health"
        }]
    },
    {
        "id": 602,
        "type": "stat",
        "title": "🔄 Alloy Restarts (24h)",
        "description": "Uses Kubernetes container restart counters in Minikube and changes in Alloy's process start time in Docker Compose. Compose requires a stable Alloy scrape target; a new Prometheus installation needs two samples before it can detect a restart.",
        "gridPos": {"h": 4, "w": 6, "x": 6, "y": 39},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 1},
                        {"color": "#ef4444", "value": 3}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "colorMode": "value",
            "graphMode": "none",
            "textMode": "value"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"observability\",container=\"alloy\"}[24h])) or sum(changes(process_start_time_seconds{job=\"alloy\"}[24h]))",
            "legendFormat": "Restarts in 24h"
        }]
    },
    {
        "id": 603,
        "type": "stat",
        "title": "💾 Alloy Memory (RSS)",
        "description": "Maximum resident set size across Alloy instances; the configured container limit is 256 MiB.",
        "gridPos": {"h": 4, "w": 6, "x": 12, "y": 39},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "bytes",
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 200000000},
                        {"color": "#ef4444", "value": 268435456}
                    ]
                }
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "colorMode": "value",
            "graphMode": "area",
            "textMode": "value"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "max(process_resident_memory_bytes{job=\"alloy\"})",
            "legendFormat": "RSS Memory"
        }]
    },
    {
        "id": 604,
        "type": "stat",
        "title": "⚡ Alloy CPU Consumption",
        "description": "Maximum CPU cores currently consumed by an Alloy instance. This is process CPU time, not percentage of the container limit.",
        "gridPos": {"h": 4, "w": 6, "x": 18, "y": 39},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "cores",
                "color": {"mode": "palette-classic"}
            }
        },
        "options": {
            "reduceOptions": {"values": False, "calcs": ["lastNotNull"]},
            "colorMode": "value",
            "graphMode": "area",
            "textMode": "value"
        },
        "targets": [{
            "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
            "expr": "max(rate(process_cpu_seconds_total{job=\"alloy\"}[5m]))",
            "legendFormat": "CPU cores"
        }]
    },
    {
        "id": 606,
        "type": "timeseries",
        "title": "⏱️ Loki Push Request Duration (ms)",
        "description": "P95 and median duration of Alloy HTTP push requests to Loki. This measures request duration, not end-to-end ingestion latency.",
        "gridPos": {"h": 7, "w": 12, "x": 0, "y": 43},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "ms",
                "color": {"mode": "palette-classic"},
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "lineWidth": 2,
                    "fillOpacity": 15,
                    "gradientMode": "opacity"
                },
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "#10b981", "value": None},
                        {"color": "#f59e0b", "value": 50},
                        {"color": "#ef4444", "value": 200}
                    ]
                }
            }
        },
        "targets": [
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "(histogram_quantile(0.95, sum by (le) (rate(loki_write_request_duration_seconds_bucket{job=\"alloy\"}[5m]))) * 1000) and (sum(rate(loki_write_request_duration_seconds_count{job=\"alloy\"}[5m])) > 0)",
                "legendFormat": "P95 request duration (ms)"
            },
            {
                "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
                "expr": "(histogram_quantile(0.50, sum by (le) (rate(loki_write_request_duration_seconds_bucket{job=\"alloy\"}[5m]))) * 1000) and (sum(rate(loki_write_request_duration_seconds_count{job=\"alloy\"}[5m])) > 0)",
                "legendFormat": "P50 request duration (ms)"
            }
        ]
    },
    {
        "id": 607,
        "type": "timeseries",
        "title": "📨 Alloy Log Flow to Loki",
        "description": "Log pipeline activity: entries successfully delivered to Loki and source lines read by Alloy, both as events per second. A live flow line confirms the pipeline is active while the adjacent panel tracks delivery failures.",
        "gridPos": {"h": 7, "w": 12, "x": 12, "y": 43},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "ops",
                "color": {"mode": "palette-classic"},
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "linear",
                    "lineWidth": 2,
                    "fillOpacity": 10,
                    "gradientMode": "opacity"
                }
            }
        },
        "targets": [
            {"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "sum(rate(loki_write_sent_entries_total{job=\"alloy\"}[5m])) or vector(0)", "legendFormat": "Entries delivered to Loki/sec"},
            {"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "sum(rate(loki_source_docker_target_entries_total{job=\"alloy\"}[5m])) or sum(rate(loki_source_file_read_lines_total{job=\"alloy\"}[5m])) or vector(0)", "legendFormat": "Log lines read by Alloy/sec"}
        ]
    },
    {
        "id": 608,
        "type": "timeseries",
        "title": "⚠️ Alloy Delivery Failures (Rolling 15m)",
        "description": "Rolling 15-minute counts of retried batches and dropped log entries grouped by drop reason. The bar view makes intermittent failures visible; zero means no failures were recorded in that window, while No data means the metric is unavailable.",
        "gridPos": {"h": 7, "w": 24, "x": 0, "y": 50},
        "datasource": {"uid": "prometheus-ds", "type": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "unit": "short",
                "color": {"mode": "palette-classic"},
                "custom": {
                    "drawStyle": "bars",
                    "lineWidth": 1,
                    "fillOpacity": 70,
                    "gradientMode": "opacity"
                }
            }
        },
        "targets": [
            {"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "sum(increase(loki_write_batch_retries_total{job=\"alloy\"}[15m]))", "legendFormat": "Retried batches / 15m"},
            {"datasource": {"uid": "prometheus-ds", "type": "prometheus"}, "expr": "sum by (reason) (increase(loki_write_dropped_entries_total{job=\"alloy\"}[15m]))", "legendFormat": "Dropped: {{reason}} / 15m"}
        ]
    }
]

    if tech.get('panels') != tech_panels:
        tech['version'] = tech.get('version', 1) + 1
    tech['panels'] = tech_panels
    # Clean up obsolete links to separated alloy dashboard
    tech['links'] = [link for link in tech.get('links', []) if link.get('url') != '/d/grafana-alloy']
    with open(tech_path, 'w', encoding='utf-8') as f:
        json.dump(tech, f, indent=2, ensure_ascii=False)

    print("Technical dashboard successfully curated with SRE, forecast API, security, and Alloy telemetry.")


def update_dashboard_files():
    """Build and write the business and technical audience-focused dashboards."""
    build_business_dashboard()
    build_technical_dashboard()


def push_dashboards(grafana_url: str = None) -> int:
    """Publish generated dashboards to GRAFANA_URL using a token or credentials from environment variables."""
    url = (grafana_url or os.getenv("GRAFANA_URL", "http://localhost:3000")).rstrip("/")
    token = os.getenv("GRAFANA_TOKEN")
    username = os.getenv("GRAFANA_USERNAME")
    password = os.getenv("GRAFANA_PASSWORD")
    if token:
        authorization = f"Bearer {token}"
    elif username and password:
        encoded = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
        authorization = f"Basic {encoded}"
    else:
        print("Error: --push requires GRAFANA_TOKEN or both GRAFANA_USERNAME and GRAFANA_PASSWORD.", file=sys.stderr)
        return 1

    headers = {"Content-Type": "application/json", "Authorization": authorization}
    for path in [biz_path, tech_path]:
        try:
            with open(path, "r", encoding="utf-8") as dashboard_file:
                dashboard = json.load(dashboard_file)
            payload = json.dumps({"dashboard": dashboard, "overwrite": True}).encode("utf-8")
            req = urllib.request.Request(f"{url}/api/dashboards/db", data=payload, headers=headers)
            with urllib.request.urlopen(req, timeout=10) as response:
                result = json.loads(response.read().decode("utf-8"))
                print(f"Pushed {path} to Grafana: {result.get('status')}")
        except Exception as e:
            print(f"Failed to push {path} to Grafana at {url}: {e}", file=sys.stderr)
            return 1

    # Remove dashboards that are now consolidated into the two audience-focused views.
    for uid, title in (
        ("grafana-alloy", "standalone Alloy"),
        ("mlops-forecast-operations", "standalone MLOps operations"),
    ):
        try:
            del_req = urllib.request.Request(f"{url}/api/dashboards/uid/{uid}", headers=headers, method="DELETE")
            with urllib.request.urlopen(del_req, timeout=10):
                print(f"Removed obsolete {title} dashboard from Grafana.")
        except urllib.error.HTTPError as error:
            if error.code != 404:
                print(f"Could not remove obsolete {title} dashboard: HTTP {error.code}.", file=sys.stderr)
                return 1
        except Exception as error:
            print(f"Could not remove obsolete {title} dashboard: {error}.", file=sys.stderr)
            return 1

    return 0


def emit_funnel_events(frontend_url: str, count: int, category: str, delay_ms: int, timeout_seconds: int) -> int:
    """Emit demo CART_ADD telemetry events for Grafana funnel panels."""
    endpoint = f"{frontend_url.rstrip('/')}/api/order/funnel"
    payload = json.dumps({"eventType": "CART_ADD", "category": category, "step": "cart"}).encode("utf-8")
    headers = {"Content-Type": "application/json", "User-Agent": "Grafana-Demo-Telemetry/1.0"}
    failures = []
    accepted = 0
    started = time.monotonic()

    print(f"Sending {count} demo CART_ADD events to {endpoint}")
    print(f"Category: {category} | Interval: {delay_ms} ms | Timeout: {timeout_seconds} s")
    for index in range(1, count + 1):
        request = urllib.request.Request(endpoint, data=payload, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
                response.read()
                if 200 <= response.status < 300:
                    accepted += 1
                else:
                    failures.append({"request": index, "status": response.status, "error": "Unexpected response"})
        except urllib.error.HTTPError as error:
            failures.append({"request": index, "status": error.code, "error": str(error.reason)})
        except Exception as error:
            failures.append({"request": index, "status": None, "error": str(error)})

        if delay_ms and index < count:
            time.sleep(delay_ms / 1000)

    print(f"Completed in {time.monotonic() - started:.2f}s: {accepted}/{count} events accepted.")
    for failure in failures[:10]:
        status = f"HTTP {failure['status']}" if failure["status"] is not None else "request failed"
        print(f"  Request {failure['request']}: {status} — {failure['error']}", file=sys.stderr)
    if len(failures) > 10:
        print(f"  ... and {len(failures) - 10} more failure(s)", file=sys.stderr)
    if failures:
        print("Check frontend/Nginx and Orders Service, then inspect the Grafana funnel panels.", file=sys.stderr)
        return 1
    print("Demo events accepted. Allow the metrics pipeline to scrape them before checking Grafana.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Unified Grafana dashboard generator and demo-telemetry operations."
    )
    # Direct flags (backward-compatible with python scripts/update_dashboards.py [--push])
    parser.add_argument("--push", action="store_true", help="Publish generated dashboards to GRAFANA_URL using environment credentials")
    parser.add_argument("--grafana-url", default=None, help="Grafana base URL")

    # Subcommands (backward-compatible with grafana.py dashboards / funnel-demo)
    subparsers = parser.add_subparsers(dest="command")

    dash_cmd = subparsers.add_parser("dashboards", help="Generate dashboard JSON files")
    dash_cmd.add_argument("--push", action="store_true", help="Publish to Grafana using configured credentials")
    dash_cmd.add_argument("--grafana-url", default=None, help="Grafana base URL")

    funnel_cmd = subparsers.add_parser("funnel-demo", help="Emit CART_ADD demo events for Grafana funnel panels")
    funnel_cmd.add_argument("--frontend-url", default=os.getenv("FRONTEND_URL", "http://127.0.0.1:5173"), help="Frontend/Nginx URL")
    funnel_cmd.add_argument("--count", type=int, default=30, help="Number of demo events (1-1000; default: 30)")
    funnel_cmd.add_argument("--category", default="Electronics", help="Event category (default: Electronics)")
    funnel_cmd.add_argument("--delay-ms", type=int, default=100, help="Pause between events, ms (0-60000; default: 100)")
    funnel_cmd.add_argument("--timeout-seconds", type=int, default=10, help="HTTP timeout per event (1-120; default: 10)")

    args = parser.parse_args()

    if args.command == "funnel-demo":
        if not 1 <= args.count <= 1000:
            parser.error("--count must be between 1 and 1000")
        if not 0 <= args.delay_ms <= 60000:
            parser.error("--delay-ms must be between 0 and 60000")
        if not 1 <= args.timeout_seconds <= 120:
            parser.error("--timeout-seconds must be between 1 and 120")
        return emit_funnel_events(args.frontend_url, args.count, args.category, args.delay_ms, args.timeout_seconds)

    # Generate dashboard JSON files (default action or 'dashboards' subcommand)
    update_dashboard_files()

    should_push = getattr(args, "push", False)
    if should_push:
        target_url = getattr(args, "grafana_url", None)
        return push_dashboards(target_url)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
