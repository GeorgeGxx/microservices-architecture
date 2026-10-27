import { TrackingNumber } from './tracking-number.vo';

describe('TrackingNumber Value Object', () => {
  it('should generate a valid DHL tracking number by default', () => {
    const tn = TrackingNumber.generate();
    expect(tn.getValue()).toMatch(/^DHL-[A-Z0-9]{8}$/);
    expect(tn.toString()).toEqual(tn.getValue());
  });

  it('should generate a valid FedEx tracking number when requested', () => {
    const tn = TrackingNumber.generate('FedEx Ground');
    expect(tn.getValue()).toMatch(/^FDX-[A-Z0-9]{8}$/);
  });

  it('should throw an error if instantiated with empty value', () => {
    expect(() => new TrackingNumber('')).toThrow('Tracking number cannot be empty');
    expect(() => new TrackingNumber('   ')).toThrow('Tracking number cannot be empty');
  });

  it('should correctly compare two tracking numbers for equality', () => {
    const tn1 = new TrackingNumber('DHL-ABC12345');
    const tn2 = new TrackingNumber('DHL-ABC12345');
    const tn3 = new TrackingNumber('DHL-XYZ99999');

    expect(tn1.equals(tn2)).toBe(true);
    expect(tn1.equals(tn3)).toBe(false);
    expect(tn1.equals(null as any)).toBe(false);
  });
});
