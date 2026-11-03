import { extractErrorMessage } from './error.util';

describe('extractErrorMessage', () => {
  it('should extract message from Error instance', () => {
    expect(extractErrorMessage(new Error('something broke'))).toBe('something broke');
  });

  it('should return string when thrown error is string', () => {
    expect(extractErrorMessage('custom string error')).toBe('custom string error');
  });

  it('should extract message property from error-like object', () => {
    expect(extractErrorMessage({ message: 'object error' })).toBe('object error');
  });

  it('should return fallback for unknown values', () => {
    expect(extractErrorMessage(null)).toBe('Unknown error');
    expect(extractErrorMessage(undefined)).toBe('Unknown error');
    expect(extractErrorMessage(123)).toBe('Unknown error');
    expect(extractErrorMessage({})).toBe('Unknown error');
  });
});
