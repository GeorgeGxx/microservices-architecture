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

export async function createProduct(payload: CreateProductPayload, token?: string): Promise<void> {
  const headers = await createHeaders(token, true);

  const res = await fetch('/api/product', {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errorText = await res.text();
    let msg = `Failed to create product [HTTP ${res.status}]`;
    try {
      const parsed = JSON.parse(errorText);
      msg = parsed.message || parsed.error || JSON.stringify(parsed);
    } catch {}
    throw new Error(msg);
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
    throw new Error(`Failed to update product [HTTP ${res.status}]: ${errorText}`);
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
    throw new Error(`Failed to delete product [HTTP ${res.status}]: ${errorText}`);
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
    let msg = `Failed to update inventory [HTTP ${res.status}]`;
    try {
      const parsed = JSON.parse(errorText);
      msg = parsed.message || parsed.error || JSON.stringify(parsed);
    } catch {}
    throw new Error(msg);
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
    throw new Error(`Failed to adjust stock [HTTP ${res.status}]: ${errorText}`);
  }
}
