package models

import "testing"

func TestOrderEventPayloadResolvers(t *testing.T) {
	tests := []struct {
		name          string
		payload       OrderEventPayload
		orderNumber   string
		status        string
		eventType     string
		amount        float64
		paymentMethod string
	}{
		{
			name: "prefers canonical fields",
			payload: OrderEventPayload{
				OrderNumber: "ORD-1", AltOrderNumber: "ORD-legacy",
				OrderStatus: "PAID", AltOrderStatus: "PENDING",
				EventType: "OrderPaid", AltEventType: "order.paid",
				TotalAmount: 42, AltTotalAmount: 99,
				PaymentMethod: "WALLET", AltPaymentMethod: "CARD_VISA",
			},
			orderNumber: "ORD-1", status: "PAID", eventType: "OrderPaid",
			amount: 42, paymentMethod: "WALLET",
		},
		{
			name: "supports legacy fields",
			payload: OrderEventPayload{
				AltOrderNumber: "ORD-2", AltOrderStatus: "CREATED",
				AltEventType: "order.created", AltTotalAmount: 25,
				AltPaymentMethod: "CARD_MASTERCARD",
			},
			orderNumber: "ORD-2", status: "CREATED", eventType: "order.created",
			amount: 25, paymentMethod: "CARD_MASTERCARD",
		},
		{
			name:          "uses payment method default",
			payload:       OrderEventPayload{},
			paymentMethod: "CARD_VISA",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			payload := &tt.payload
			if got := payload.ResolveOrderNumber(); got != tt.orderNumber {
				t.Errorf("ResolveOrderNumber() = %q, want %q", got, tt.orderNumber)
			}
			if got := payload.ResolveStatus(); got != tt.status {
				t.Errorf("ResolveStatus() = %q, want %q", got, tt.status)
			}
			if got := payload.ResolveEventType(); got != tt.eventType {
				t.Errorf("ResolveEventType() = %q, want %q", got, tt.eventType)
			}
			if got := payload.ResolveAmount(); got != tt.amount {
				t.Errorf("ResolveAmount() = %v, want %v", got, tt.amount)
			}
			if got := payload.ResolvePaymentMethod(); got != tt.paymentMethod {
				t.Errorf("ResolvePaymentMethod() = %q, want %q", got, tt.paymentMethod)
			}
		})
	}
}
