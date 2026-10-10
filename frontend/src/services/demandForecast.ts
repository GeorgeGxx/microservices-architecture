import { getValidAccessToken } from './keycloak';

export interface DemandForecastDay {
  date: string;
  units: number;
}

export interface ProductDemandForecast {
  sku: string;
  status: 'READY' | 'INSUFFICIENT_HISTORY';
  historyDays: number;
  forecasts: DemandForecastDay[];
  totalUnits: number | null;
}

export interface DemandForecastResponse {
  horizonDays: 7;
  dataSource: 'synthetic' | 'captured-sales';
  generatedAt: string;
  modelRunId: string;
  modelCreatedAt: string;
  historyStartDate: string;
  historyEndDate: string;
  products: ProductDemandForecast[];
}

export async function fetchDemandForecast(token?: string): Promise<DemandForecastResponse> {
  const accessToken = await getValidAccessToken(token);
  const headers: Record<string, string> = {};
  if (accessToken) headers.Authorization = `Bearer ${accessToken}`;

  const response = await fetch('/api/forecast', { headers });
  if (!response.ok) {
    let detail = `Forecast service returned HTTP ${response.status}`;
    try {
      const body = await response.json();
      if (body.detail) detail = body.detail;
    } catch {}
    throw new Error(detail);
  }

  return response.json() as Promise<DemandForecastResponse>;
}
