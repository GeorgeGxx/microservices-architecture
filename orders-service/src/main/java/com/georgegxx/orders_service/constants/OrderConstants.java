package com.georgegxx.orders_service.constants;

import lombok.AccessLevel;
import lombok.NoArgsConstructor;

/**
 * Platform constants and default configuration values for the Orders Bounded Context.
 * Eliminates magic strings and numbers across controllers, services, and event publishers.
 */
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class OrderConstants {

    // Service Identifiers & Kafka Topics
    public static final String INVENTORY_SERVICE = "inventory-service";
    public static final String PRODUCTS_SERVICE = "products-service";
    public static final String ORDERS_SERVICE = "orders-service";
    public static final String ORDERS_TOPIC = "orders-topic";
    public static final String PAYMENTS_TOPIC = "payments-topic";
    public static final String FULFILLMENT_TOPIC = "fulfillment-topic";
    public static final String SAGA_CONSUMER_GROUP = "orders-saga-group";

    // Choreographed Saga Event Types
    public static final String EVENT_PAYMENT_COMPLETED = "PAYMENT_COMPLETED";
    public static final String EVENT_PAYMENT_FAILED = "PAYMENT_FAILED";
    public static final String EVENT_PAYMENT_REFUNDED = "PAYMENT_REFUNDED";
    public static final String EVENT_SHIPMENT_DISPATCHED = "SHIPMENT_DISPATCHED";
    public static final String EVENT_SHIPMENT_DELIVERED = "SHIPMENT_DELIVERED";
    public static final String EVENT_SHIPMENT_FAILED = "SHIPMENT_FAILED";

    // Logistics & Carrier Defaults
    public static final String DEFAULT_DELIVERY_METHOD = "STANDARD";
    public static final String DEFAULT_CARRIER = "DHL Express";
    public static final String TRACKING_PREFIX = "DHL-";
    public static final String DEFAULT_PAYMENT_METHOD = "CARD_VISA";

    // Pricing & Financial Calculation Defaults
    public static final double DEFAULT_FREE_SHIPPING_THRESHOLD_USD = 100.0;
    public static final double DEFAULT_SHIPPING_FEE_USD = 9.99;
    public static final double DEFAULT_TAX_RATE = 0.08;
    public static final double STALE_PRICE_WARN_THRESHOLD = 0.01; // 1%

    // Metric Tags and Names
    public static final String STATUS_TAG = "status";
    public static final String TAG_EVENT_TYPE = "event_type";
    public static final String TAG_CATEGORY = "category";
    public static final String TAG_STEP = "step";
    public static final String METRIC_ECOMMERCE_SKU_SALES = "ecommerce_sku_sales";
    public static final String METRIC_ECOMMERCE_FUNNEL_EVENTS = "ecommerce_funnel_events";

    // Customer Loyalty Cohorts
    public static final String COHORT_FIRST_TIME = "first_time";
    public static final String COHORT_REPEAT = "repeat";
    public static final String COHORT_LOYAL_VIP = "loyal_vip";

    // Basket Size Distributions
    public static final String BASKET_SINGLE_ITEM = "single_item";
    public static final String BASKET_2_3_ITEMS = "2_3_items";
    public static final String BASKET_BULK_4_PLUS = "bulk_4_plus";

    // Error Messages & Templates
    public static final String ORDER_ID_NOT_NULL_MSG = "Order ID must not be null";
    public static final String ORDER_NOT_FOUND_PREFIX = "Order with id ";
    public static final String ORDER_NOT_FOUND_SUFFIX = " not found";

    // Security & Roles
    public static final String ROLE_ADMIN = "ADMIN";
    public static final String ROLE_USER = "USER";
    public static final String CLAIM_REALM_ACCESS = "realm_access";
    public static final String CLAIM_ROLES = "roles";
    public static final String CLAIM_PREFERRED_USERNAME = "preferred_username";
}
