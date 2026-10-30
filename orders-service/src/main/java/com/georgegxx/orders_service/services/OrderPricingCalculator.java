package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.constants.OrderConstants;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Domain service responsible for order financial calculations.
 * Encapsulates pricing invariants, free shipping thresholds, sales tax computation,
 * and high-precision currency rounding.
 */
@Component
public class OrderPricingCalculator {

    /**
     * Immutable value object holding calculated order financial breakdown.
     */
    public record FinancialBreakdown(
            double subtotalAmount,
            double shippingFee,
            double taxAmount,
            double totalAmount
    ) {}

    /**
     * Calculates the complete financial breakdown based on the verified subtotal.
     *
     * @param rawSubtotal the raw subtotal sum of order line items
     * @return the calculated FinancialBreakdown
     */
    public FinancialBreakdown calculateBreakdown(double rawSubtotal) {
        double subtotal = roundCurrency(rawSubtotal);
        double shipping = subtotal >= OrderConstants.DEFAULT_FREE_SHIPPING_THRESHOLD_USD
                ? 0.0
                : OrderConstants.DEFAULT_SHIPPING_FEE_USD;
        double tax = roundCurrency(subtotal * OrderConstants.DEFAULT_TAX_RATE);
        double total = roundCurrency(subtotal + shipping + tax);

        return new FinancialBreakdown(subtotal, shipping, tax, total);
    }

    /**
     * Rounds a monetary double amount to 2 decimal places using HALF_UP rounding.
     *
     * @param amount the double value to round
     * @return rounded value
     */
    public double roundCurrency(double amount) {
        return BigDecimal.valueOf(amount)
                .setScale(2, RoundingMode.HALF_UP)
                .doubleValue();
    }
}
