import { v4 as uuidv4 } from 'uuid';

export class TrackingNumber {
  private readonly value: string;

  constructor(value: string) {
    if (!value || value.trim().length === 0) {
      throw new Error('Tracking number cannot be empty');
    }
    this.value = value.trim().toUpperCase();
  }

  public static generate(carrier = 'DHL Express'): TrackingNumber {
    const prefix = carrier.toUpperCase().includes('FEDEX') ? 'FDX' : 'DHL';
    const uniqueSuffix = uuidv4().substring(0, 8).toUpperCase();
    return new TrackingNumber(`${prefix}-${uniqueSuffix}`);
  }

  public getValue(): string {
    return this.value;
  }

  public equals(other: TrackingNumber): boolean {
    if (!other) return false;
    return this.value === other.getValue();
  }

  public toString(): string {
    return this.value;
  }
}
