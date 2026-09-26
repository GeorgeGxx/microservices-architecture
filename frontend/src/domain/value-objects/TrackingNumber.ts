export class TrackingNumber {
  public readonly code: string;
  public readonly carrier: string;

  constructor(code: string, carrier = 'DHL Express') {
    this.code = code ? code.trim() : TrackingNumber.generateMockDHL();
    this.carrier = carrier;
  }

  public getTrackingUrl(): string {
    if (this.carrier.toUpperCase().includes('DHL')) {
      return `https://www.dhl.com/en/express/tracking.html?AWB=${encodeURIComponent(this.code)}`;
    }
    return `https://www.google.com/search?q=${encodeURIComponent(this.carrier + ' ' + this.code)}`;
  }

  public isDhl(): boolean {
    return this.carrier.toUpperCase().includes('DHL');
  }

  public static generateMockDHL(): string {
    const randomSuffix = Math.floor(10000000 + Math.random() * 90000000);
    return `DHL-EXP-${randomSuffix}`;
  }
}
