type GraphQLHealthResponse = {
  data?: { products?: Array<{ sku: string }> | null };
  errors?: Array<{ message?: string }>;
};

/** Checks the browser-to-Nginx-to-Apollo-to-Products path without loading the catalog. */
export async function checkStorefrontApiHealth(signal?: AbortSignal): Promise<boolean> {
  const response = await fetch('/graphql', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: 'query StorefrontHealth { products { sku } }' }),
    cache: 'no-store',
    signal,
  });

  if (!response.ok) return false;

  const result = (await response.json()) as GraphQLHealthResponse;
  return !result.errors?.length && Array.isArray(result.data?.products);
}
