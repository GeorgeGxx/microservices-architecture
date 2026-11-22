import { jest } from '@jest/globals';

jest.mock('@sentry/nestjs', () => ({ init: jest.fn() }));

describe('GlitchTip event privacy configuration', () => {
  const originalEnvironment = process.env;
  let beforeSend: (event: any) => any;

  beforeAll(async () => {
    jest.resetModules();
    process.env = {
      ...originalEnvironment,
      OTEL_SERVICE_NAME: 'fulfillment-test',
      APP_ENV: 'test',
      APP_RELEASE: 'test-release',
      SENTRY_DSN: 'https://public@example.invalid/1',
    };
    await import('./glitchtip');
    const sentry = await import('@sentry/nestjs');
    const initOptions = jest.mocked(sentry.init).mock.calls.at(-1)?.[0];
    if (!initOptions?.beforeSend) throw new Error('GlitchTip beforeSend hook was not registered');
    beforeSend = initOptions.beforeSend as (event: any) => any;
  });

  afterAll(() => {
    process.env = originalEnvironment;
    jest.restoreAllMocks();
  });

  it('removes request, user, contexts, extras, breadcrumbs and message data', () => {
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

    const sanitized = beforeSend(event);

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

  it('uses a safe environment tag when the event has no environment', () => {
    expect(beforeSend({ exception: { values: [] } }).tags).toEqual({
      service: 'fulfillment-test',
      environment: 'unknown',
    });
  });

  it('handles events without exception values', () => {
    expect(beforeSend({}).exception).toBeUndefined();
  });
});
