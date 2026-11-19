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
			assertResolverEqual(t, "ResolveOrderNumber", payload.ResolveOrderNumber(), tt.orderNumber)
			assertResolverEqual(t, "ResolveStatus", payload.ResolveStatus(), tt.status)
			assertResolverEqual(t, "ResolveEventType", payload.ResolveEventType(), tt.eventType)
			assertResolverEqual(t, "ResolveAmount", payload.ResolveAmount(), tt.amount)
			assertResolverEqual(t, "ResolvePaymentMethod", payload.ResolvePaymentMethod(), tt.paymentMethod)
		})
	}
}

func assertResolverEqual[T comparable](t *testing.T, name string, got, want T) {
	t.Helper()
	if got != want {
		t.Errorf("%s() = %v, want %v", name, got, want)
	}
}
