import { Component, ChangeDetectionStrategy, inject, signal, computed, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterModule } from '@angular/router';
import { CartStore } from '../../core/services/cart.store';
import { OrderService } from '../../core/services/order.service';
import { KeycloakService } from '../../core/auth/keycloak.service';
import { ToastService } from '../../core/services/toast.service';
import { NotificationCenterService } from '../../core/services/notification-center.service';
import { OrderRequest, OrderResponse } from '../../core/models/order.model';
import { ReceiptModalComponent } from '../../shared/components/receipt-modal/receipt-modal.component';
import { OrderStepperComponent } from '../../shared/components/order-stepper/order-stepper.component';
import { CurrencyService } from '../../core/services/currency.service';
import { ProductService } from '../../core/services/product.service';
import { getProductImageUrl } from '../../core/utils/product-image.helper';

export type DeliveryMethod = 'STANDARD' | 'EXPRESS';
export type CardBrand = 'visa' | 'mastercard' | 'amex' | 'generic';

@Component({
  selector: 'app-checkout',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterModule, ReceiptModalComponent, OrderStepperComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './checkout.component.html',
  styleUrl: './checkout.component.css'
})
export class CheckoutComponent implements OnInit {
  readonly cartStore = inject(CartStore);
  private readonly productService = inject(ProductService);
  readonly getProductImageUrl = getProductImageUrl;
  private readonly orderService = inject(OrderService);
  readonly currencyService = inject(CurrencyService);
  readonly keycloakService = inject(KeycloakService);
  private readonly toastService = inject(ToastService);
  private readonly notifService = inject(NotificationCenterService);

  readonly isPlacingOrder = signal<boolean>(false);
  readonly completedOrder = signal<OrderResponse | null>(null);
  readonly showReceiptModal = signal<boolean>(false);

  // Multi-step Checkout Flow (1 = Address, 2 = Shipping Speed, 3 = Payment)
  readonly currentStep = signal<number>(1);

  // Step 1: Shipping Address
  readonly customerName = signal<string>('');
  readonly customerEmail = signal<string>('');
  readonly shippingAddress = signal<string>('');
  readonly city = signal<string>('');
  readonly postalCode = signal<string>('');
  readonly phone = signal<string>('');
  readonly saveAddress = signal<boolean>(true);

  // Step 2: Delivery Speed
  readonly deliveryMethod = signal<DeliveryMethod>('STANDARD');

  // Step 3: Payment Method
  readonly paymentType = signal<'CARD' | 'PAYPAL'>('CARD');
  readonly cardNumber = signal<string>('4532 8901 2345 6789');
  readonly cardHolder = signal<string>('');
  readonly cardExp = signal<string>('12/28');
  readonly cardCvv = signal<string>('842');

  // Card Brand Detection
  readonly cardBrand = computed<CardBrand>(() => {
    const raw = this.cardNumber().replace(/\s+/g, '');
    if (raw.startsWith('4')) return 'visa';
    if (/^(5[1-5]|2[2-7])/.test(raw)) return 'mastercard';
    if (/^(34|37)/.test(raw)) return 'amex';
    return 'generic';
  });

  // Financial calculations
  readonly subtotal = computed(() => this.cartStore.totalAmount());
  readonly shippingFee = computed(() => this.deliveryMethod() === 'EXPRESS' ? 9.99 : 0.0);
  readonly taxAmount = computed(() => Math.round(this.subtotal() * 0.08 * 100) / 100);
  readonly totalAmount = computed(() => Math.round((this.subtotal() + this.shippingFee() + this.taxAmount()) * 100) / 100);

  // Estimated delivery date string
  readonly estimatedArrival = computed(() => {
    const now = new Date();
    const daysToAdd = this.deliveryMethod() === 'EXPRESS' ? 2 : 5;
    now.setDate(now.getDate() + daysToAdd);
    return now.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
  });

  ngOnInit(): void {
    // Populate user details from Keycloak and saved address
    const profile = this.keycloakService.userProfile();
    const username = profile?.username || 'Customer';
    const email = profile?.email || `${username.toLowerCase()}@example.com`;

    try {
      const saved = localStorage.getItem('msa_shipping_address');
      if (saved) {
        const parsed = JSON.parse(saved);
        this.customerName.set(parsed.customerName || username);
        this.customerEmail.set(parsed.customerEmail || email);
        this.shippingAddress.set(parsed.shippingAddress || '100 Silicon Way');
        this.city.set(parsed.city || 'San Francisco');
        this.postalCode.set(parsed.postalCode || '94105');
        this.phone.set(parsed.phone || '+1 (555) 019-2834');
        this.cardHolder.set(parsed.customerName?.toUpperCase() || username.toUpperCase());
        return;
      }
    } catch {}

    this.customerName.set(username);
    this.customerEmail.set(email);
    this.shippingAddress.set('100 Silicon Way');
    this.city.set('San Francisco');
    this.postalCode.set('94105');
    this.phone.set('+1 (555) 019-2834');
    this.cardHolder.set(username.toUpperCase());

    // Record initial checkout funnel events
    this.orderService.recordFunnelEvent('CHECKOUT_START');
    this.orderService.recordFunnelEvent('CHECKOUT_STEP', { step: 'shipping' });
  }

  goToStep(step: number): void {
    if (step === 2 && !this.validateAddressStep()) return;
    this.currentStep.set(step);

    const stepName = step === 1 ? 'shipping' : step === 2 ? 'delivery' : 'payment';
    this.orderService.recordFunnelEvent('CHECKOUT_STEP', { step: stepName });
  }

  setDeliveryMethod(method: DeliveryMethod): void {
    this.deliveryMethod.set(method);
  }

  formatCardNumber(event: Event): void {
    const input = event.target as HTMLInputElement;
    let value = input.value.replace(/\D+/g, '').substring(0, 16);
    const parts = value.match(/.{1,4}/g);
    this.cardNumber.set(parts ? parts.join(' ') : value);
  }

  validateAddressStep(): boolean {
    if (!this.customerName().trim() || !this.shippingAddress().trim() || !this.city().trim()) {
      this.toastService.warning('Required Information', 'Please fill in your recipient name, address, and city.');
      return false;
    }
    if (this.saveAddress()) {
      try {
        localStorage.setItem('msa_shipping_address', JSON.stringify({
          customerName: this.customerName(),
          customerEmail: this.customerEmail(),
          shippingAddress: this.shippingAddress(),
          city: this.city(),
          postalCode: this.postalCode(),
          phone: this.phone()
        }));
      } catch {}
    }
    return true;
  }

  submitOrder(): void {
    if (!this.keycloakService.isAuthenticated()) {
      this.toastService.warning('Authentication Required', 'Please sign in with Keycloak to place an order.');
      this.keycloakService.login();
      return;
    }

    const items = this.cartStore.items();
    if (items.length === 0) {
      this.toastService.warning('Cart is Empty', 'Please add products before checking out.');
      return;
    }

    if (!this.validateAddressStep()) {
      this.currentStep.set(1);
      return;
    }

    // Persist products into cache to guarantee image consistency in orders view
    this.productService.cacheProducts(items.map(item => item.product));

    this.isPlacingOrder.set(true);

    const orderRequest: OrderRequest = {
      orderItems: items.map(item => ({
        sku: item.product.sku,
        price: this.currencyService.getProductPrice(item.product),
        quantity: item.quantity
      })),
      customerName: this.customerName(),
      customerEmail: this.customerEmail(),
      shippingAddress: this.shippingAddress(),
      city: this.city(),
      postalCode: this.postalCode(),
      phone: this.phone(),
      deliveryMethod: this.deliveryMethod(),
      shippingFee: this.shippingFee(),
      taxAmount: this.taxAmount(),
      totalAmount: this.totalAmount(),
      paymentMethod: `${this.paymentType()}_${this.cardBrand().toUpperCase()}`
    };

    this.orderService.placeOrder(orderRequest).subscribe({
      next: (response) => {
        this.isPlacingOrder.set(false);
        this.completedOrder.set(response);
        this.cartStore.clearCart();
        const shortNum = response.orderNumber ? response.orderNumber.substring(0, 8).toUpperCase() : '';
        const tracking = response.trackingNumber || 'DHL Express';
        const title = `Order #${shortNum} Confirmed!`;
        const message = `Your package is being prepared for dispatch via ${tracking} to ${response.city || 'your address'}.`;
        this.notifService.addNotification({
          title,
          message,
          type: 'success'
        });
        this.toastService.success(title, message);
      },
      error: (err) => {
        this.isPlacingOrder.set(false);
        const errMsg = err?.error?.message || err?.message || 'Unable to communicate with Orders Service. Please try again.';
        this.toastService.error('Order Placement Failed', errMsg);
      }
    });
  }

  openReceipt(): void {
    this.showReceiptModal.set(true);
  }

  closeReceipt(): void {
    this.showReceiptModal.set(false);
  }

  onCompletedOrderStatusUpdated(event: { orderId?: number; status: 'PLACED' | 'CANCELLED' | 'SHIPPED' | 'DELIVERED' }): void {
    if (this.completedOrder()) {
      this.completedOrder.update(o => o ? { ...o, orderStatus: event.status } : null);
    }
  }
}
