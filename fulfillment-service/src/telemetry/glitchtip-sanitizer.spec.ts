import { sanitizeGlitchTipEvent } from './glitchtip-sanitizer';

describe('GlitchTip event privacy sanitizer', () => {
  it('removes personal and request data and redacts exception details', () => {
    const event = {
      request: { url: '/private?token=secret' },
      user: { email: 'person@example.com' },
      contexts: { runtime: { name: 'node' } },
      extra: { password: 'secret' },
      breadcrumbs: [{ message: 'sensitive' }],
      message: 'sensitive message',
      transaction: '/private/transaction',
      environment: 'test',
      exception: { values: [{ value: 'database password leaked', mechanism: { data: { password: 'secret' } } }] },
    };

    const sanitized = sanitizeGlitchTipEvent(event, 'fulfillment-test');

    expect(sanitized).toMatchObject({
      request: undefined,
      user: undefined,
      contexts: undefined,
      extra: undefined,
      breadcrumbs: [],
      message: undefined,
      transaction: undefined,
      tags: { service: 'fulfillment-test', environment: 'test' },
      exception: { values: [{ value: '[redacted]', mechanism: {} }] },
    });
  });

  it('uses a safe environment tag when the event has none', () => {
    expect(sanitizeGlitchTipEvent({}, 'fulfillment-test').tags).toEqual({
      service: 'fulfillment-test',
      environment: 'unknown',
    });
  });

  it('handles events without exception values', () => {
    expect(sanitizeGlitchTipEvent({}, 'fulfillment-test').exception).toBeUndefined();
  });
});
