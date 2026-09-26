export type CheckoutStep =
  | 'CUSTOMER_INFO'
  | 'DELIVERY_TIER'
  | 'PAYMENT'
  | 'PROCESSING'
  | 'CONFIRMED'
  | 'FAILED';

export interface CheckoutContextData {
  customerName: string;
  customerEmail: string;
  shippingAddress: string;
  city: string;
  postalCode: string;
  phone: string;
  deliveryMethod: string;
  paymentMethod: string;
  cardNumber: string;
  cardExpiry: string;
  cardCvv: string;
}

export class CheckoutStateMachine {
  private currentStep: CheckoutStep = 'CUSTOMER_INFO';
  private error: string | null = null;

  public get step(): CheckoutStep {
    return this.currentStep;
  }

  public get errorMessage(): string | null {
    return this.error;
  }

  public canTransitionTo(target: CheckoutStep, data: CheckoutContextData): boolean {
    switch (target) {
      case 'CUSTOMER_INFO':
        return this.currentStep !== 'PROCESSING' && this.currentStep !== 'CONFIRMED';

      case 'DELIVERY_TIER':
        if (this.currentStep === 'CUSTOMER_INFO') {
          return (
            data.customerName.trim().length > 0 &&
            data.customerEmail.includes('@') &&
            data.shippingAddress.trim().length >= 5
          );
        }
        return this.currentStep === 'PAYMENT';

      case 'PAYMENT':
        if (this.currentStep === 'DELIVERY_TIER') {
          return data.deliveryMethod.length > 0;
        }
        return false;

      case 'PROCESSING':
        if (this.currentStep === 'PAYMENT') {
          return data.cardNumber.replace(/\s/g, '').length >= 15 && data.cardCvv.length >= 3;
        }
        return false;

      case 'CONFIRMED':
        return this.currentStep === 'PROCESSING';

      case 'FAILED':
        return this.currentStep === 'PROCESSING';

      default:
        return false;
    }
  }

  public transition(target: CheckoutStep, data: CheckoutContextData): boolean {
    if (this.canTransitionTo(target, data)) {
      this.currentStep = target;
      this.error = null;
      return true;
    }
    this.error = `Invalid transition from ${this.currentStep} to ${target}. Please verify required fields.`;
    return false;
  }

  public forceFail(message: string): void {
    this.currentStep = 'FAILED';
    this.error = message;
  }

  public retry(): void {
    if (this.currentStep === 'FAILED') {
      this.currentStep = 'PAYMENT';
      this.error = null;
    }
  }

  public reset(): void {
    this.currentStep = 'CUSTOMER_INFO';
    this.error = null;
  }
}
