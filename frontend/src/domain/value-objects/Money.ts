export type CurrencyCode = 'USD';

export class Money {
  public readonly amount: number;
  public readonly currency: CurrencyCode;

  constructor(amount: number, currency: CurrencyCode = 'USD') {
    if (isNaN(amount) || amount < 0) {
      this.amount = 0;
    } else {
      this.amount = Math.round(amount * 100) / 100;
    }
    this.currency = 'USD';
  }

  public add(other: Money): Money {
    return new Money(this.amount + other.amount, 'USD');
  }

  public subtract(other: Money): Money {
    return new Money(Math.max(0, this.amount - other.amount), 'USD');
  }

  public multiply(factor: number): Money {
    return new Money(this.amount * factor, 'USD');
  }

  public convertTo(_targetCurrency: CurrencyCode = 'USD'): Money {
    return this;
  }

  public format(): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(this.amount);
  }

  public equals(other: Money): boolean {
    return Math.abs(this.amount - other.amount) < 0.001;
  }

  public static zero(currency: CurrencyCode = 'USD'): Money {
    return new Money(0, currency);
  }
}
