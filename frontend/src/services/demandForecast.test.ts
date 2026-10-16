import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { fetchDemandForecast, DemandForecastResponse } from './demandForecast';
import * as keycloakService from './keycloak';

describe('fetchDemandForecast', () => {
  const originalFetch = globalThis.fetch;

  const mockResponse: DemandForecastResponse = {
    horizonDays: 7,
    dataSource: 'synthetic',
    generatedAt: '2026-10-16T10:00:00Z',
    modelRunId: 'run-001',
    modelCreatedAt: '2026-10-16T08:00:00Z',
    historyStartDate: '2026-10-01',
    historyEndDate: '2026-10-15',
    products: [
      {
        sku: 'LAPTOP-PRO',
        status: 'READY',
        historyDays: 14,
        forecasts: [{ date: '2026-10-16', units: 5 }],
        totalUnits: 35,
      },
    ],
  };

  beforeEach(() => {
    vi.spyOn(keycloakService, 'getValidAccessToken').mockImplementation(async (token) => token || 'mock-valid-token');
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
    vi.restoreAllMocks();
  });

  it('fetches forecast successfully with authorization header', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => mockResponse,
    } as Response);

    const result = await fetchDemandForecast('passed-token');

    expect(result).toEqual(mockResponse);
    expect(globalThis.fetch).toHaveBeenCalledWith(
      '/api/forecast',
      expect.objectContaining({
        headers: { Authorization: 'Bearer passed-token' },
      })
    );
  });

  it('throws service error detail when HTTP request fails with JSON body', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 503,
      json: async () => ({ detail: 'Forecast model is currently retraining' }),
    } as Response);

    await expect(fetchDemandForecast()).rejects.toThrow('Forecast model is currently retraining');
  });

  it('throws fallback status message when HTTP request fails without json body', async () => {
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
      json: async () => {
        throw new Error('Not JSON');
      },
    } as unknown as Response);

    await expect(fetchDemandForecast()).rejects.toThrow('Forecast service returned HTTP 500');
  });
});
