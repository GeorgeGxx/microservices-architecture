package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.constants.OrderConstants;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class OrderPricingCalculatorTest {

    private OrderPricingCalculator calculator;

    @BeforeEach
    void setUp() {
        calculator = new OrderPricingCalculator();
    }

    @Test
    @DisplayName("Subtotal under threshold applies standard shipping fee and 8% tax")
    void testCalculateBreakdown_UnderFreeShippingThreshold() {
        double subtotal = 50.00;
        OrderPricingCalculator.FinancialBreakdown breakdown = calculator.calculateBreakdown(subtotal);

        assertEquals(50.00, breakdown.subtotalAmount());
        assertEquals(OrderConstants.DEFAULT_SHIPPING_FEE_USD, breakdown.shippingFee());
        assertEquals(4.00, breakdown.taxAmount()); // 50 * 0.08 = 4.00
        assertEquals(63.99, breakdown.totalAmount()); // 50 + 9.99 + 4.00 = 63.99
    }

    @Test
    @DisplayName("Subtotal equal or above $100 qualifies for free shipping")
    void testCalculateBreakdown_FreeShippingEligible() {
        double subtotal = 100.00;
        OrderPricingCalculator.FinancialBreakdown breakdown = calculator.calculateBreakdown(subtotal);

        assertEquals(100.00, breakdown.subtotalAmount());
        assertEquals(0.00, breakdown.shippingFee());
        assertEquals(8.00, breakdown.taxAmount()); // 100 * 0.08 = 8.00
        assertEquals(108.00, breakdown.totalAmount());
    }

    @Test
    @DisplayName("Currency rounding handles high-precision floating point properly with HALF_UP")
    void testRoundCurrency() {
        assertEquals(12.35, calculator.roundCurrency(12.345));
        assertEquals(12.34, calculator.roundCurrency(12.344));
        assertEquals(0.00, calculator.roundCurrency(0.0001));
    }
}
