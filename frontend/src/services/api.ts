import { getValidAccessToken } from './keycloak';

async function createHeaders(token?: string, json = false): Promise<Record<string, string>> {
  const headers: Record<string, string> = {};
  if (json) headers['Content-Type'] = 'application/json';

  const accessToken = await getValidAccessToken(token);
  if (accessToken) headers['Authorization'] = `Bearer ${accessToken}`;
  return headers;
}

export interface CreateProductPayload {
  sku: string;
  name: string;
  description?: string;
  price: number;
  status: boolean;
  imageUrl?: string;
  category?: string;
  rating?: number;
  reviewCount?: number;
  isBestSeller?: boolean;
}

export interface InventoryPayload {
  sku: string;
  quantity: number;
}

export function extractApiErrorMessage(errorText: string, status: number, defaultPrefix: string): string {
  try {
    const parsed = JSON.parse(errorText);
    if (parsed.fields && typeof parsed.fields === 'object') {
      const fieldList = Object.entries(parsed.fields)
        .map(([k, v]) => `${k}: ${v}`)
        .join(', ');
      if (fieldList) return fieldList;
    }
    if (parsed.detail) {
      if (typeof parsed.detail === 'object') {
        const detailList = Object.entries(parsed.detail)
          .map(([k, v]) => `${k}: ${v}`)
          .join(', ');
        if (detailList) return detailList;
      }
      return String(parsed.detail);
    }
    if (parsed.message) return parsed.message;
    if (parsed.error) return parsed.error;
    return JSON.stringify(parsed);
  } catch {
    return errorText || `${defaultPrefix} [HTTP ${status}]`;
  }
}

export async function createProduct(payload: CreateProductPayload, token?: string): Promise<void> {
  const headers = await createHeaders(token, true);

  const res = await fetch('/api/product', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to create product'));
  }
}

export async function updateProduct(id: string | number, payload: CreateProductPayload, token?: string): Promise<void> {
  const headers = await createHeaders(token, true);

  const res = await fetch(`/api/product/${id}`, {
    method: 'PUT',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to update product'));
  }
}

export async function deleteProduct(id: string | number, token?: string): Promise<void> {
  const headers = await createHeaders(token);

  const res = await fetch(`/api/product/${id}`, {
    method: 'DELETE',
    headers,
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to delete product'));
  }
}

export async function saveOrUpdateStock(payload: InventoryPayload, token?: string): Promise<void> {
  const headers = await createHeaders(token, true);

  const res = await fetch('/api/inventory', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to update inventory'));
  }
}

export async function updateStockQuantity(sku: string, quantity: number, token?: string): Promise<void> {
  const headers = await createHeaders(token);

  const res = await fetch(`/api/inventory/${encodeURIComponent(sku)}?quantity=${Math.max(0, quantity)}`, {
    method: 'PUT',
    headers,
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to adjust stock'));
  }
}

export interface InventoryDetailResponse {
  id?: number;
  sku: string;
  quantity: number;
  isInStock?: boolean;
}

export async function fetchInventoryBySku(sku: string, token?: string): Promise<InventoryDetailResponse | null> {
  const headers = await createHeaders(token);
  const res = await fetch(`/api/inventory/detail/${encodeURIComponent(sku)}`, {
    headers,
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(extractApiErrorMessage(errorText, res.status, 'Failed to fetch inventory detail'));
  }
  return res.json();
}

export interface FunnelTelemetryPayload {
  eventType: string;
  sku?: string;
  category?: string;
  step?: string;
}

export async function recordFunnelTelemetry(payload: FunnelTelemetryPayload, token?: string): Promise<void> {
  try {
    const headers = await createHeaders(token, true);
    const analyticsPayload = {
      event_type: payload.eventType,
      category: payload.category || 'General',
      step: payload.step,
      metadata: payload.sku ? { sku: payload.sku } : {},
    };

    await Promise.allSettled([
      fetch('/api/v1/analytics/events', {
        method: 'POST',
        headers,
        body: JSON.stringify(analyticsPayload),
      }),
      fetch('/api/order/funnel', {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
      }),
    ]);
  } catch {
    // Non-blocking telemetry
  }
}

