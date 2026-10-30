export class ShippingAddress {
  constructor(
    public readonly recipientName: string,
    public readonly street: string,
    public readonly city: string,
    public readonly postalCode: string,
    public readonly phone?: string,
  ) {
    if (!recipientName || recipientName.trim().length === 0) {
      throw new Error('Recipient name is required');
    }
    if (!street || street.trim().length === 0) {
      throw new Error('Street address is required');
    }
    if (!city || city.trim().length === 0) {
      throw new Error('City is required');
    }
  }

  public getFullAddress(): string {
    return `${this.street}, ${this.city} ${this.postalCode || ''}`.trim();
  }
}
