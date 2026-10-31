type GraphQLHealthResponse = {
  data?: { products?: Array<{ sku: string }> | null };
  errors?: Array<{ message?: string }>;
};

export type StorefrontHealthResult = 'healthy' | 'throttled' | 'unavailable';

/** Checks the browser-to-Nginx-to-Apollo-to-Products path without loading the catalog. */
export async function checkStorefrontApiHealth(signal?: AbortSignal): Promise<StorefrontHealthResult> {
  try {
    const response = await fetch('/graphql', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query: 'query StorefrontHealth { products { sku } }' }),
      cache: 'no-store',
      signal,
    });

    if (response.status === 429) {
      return 'throttled';
    }

    if (!response.ok) {
      // If /graphql was rejected or blocked, check unthrottled router-health to verify if gateway is alive
      try {
        const routerResp = await fetch('/router-health', { cache: 'no-store', signal });
        if (routerResp.ok) {
          return 'throttled';
        }
      } catch {
        // Router health unreachable
      }
      return 'unavailable';
    }

    const result = (await response.json()) as GraphQLHealthResponse;
    return (!result.errors?.length && Array.isArray(result.data?.products)) ? 'healthy' : 'unavailable';
  } catch {
    // In case of network timeout / drop, probe unthrottled router-health
    try {
      const routerResp = await fetch('/router-health', { cache: 'no-store', signal });
      if (routerResp.ok) {
        return 'throttled';
      }
    } catch {
      // offline
    }
    return 'unavailable';
  }
}
