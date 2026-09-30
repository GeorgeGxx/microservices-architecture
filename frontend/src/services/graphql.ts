import { Product, Order, InventoryItem, PlaceOrderInput } from '../types';
import { getValidAccessToken } from './keycloak';

const GRAPHQL_ENDPOINT = '/graphql';

interface GraphQLResponse<T> {
  data?: T;
  errors?: Array<{ message: string; locations?: unknown[]; path?: string[] }>;
}

export async function executeGraphQL<T>(
  query: string,
  variables: Record<string, unknown> = {},
  token?: string,
  idempotencyKey?: string,
  timeoutMs?: number
): Promise<T> {
  const accessToken = await getValidAccessToken(token);
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (accessToken) {
    headers['Authorization'] = `Bearer ${accessToken}`;
  }

  if (idempotencyKey) {
    headers['X-Idempotency-Key'] = idempotencyKey;
  }

  const controller = timeoutMs ? new AbortController() : undefined;
  const timeoutId = controller && timeoutMs
    ? window.setTimeout(() => controller.abort(), timeoutMs)
    : undefined;

  try {
    const response = await fetch(GRAPHQL_ENDPOINT, {
      method: 'POST',
      headers,
      body: JSON.stringify({ query, variables }),
      signal: controller?.signal,
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`GraphQL HTTP error [${response.status}]: ${errorText}`);
    }

    const result: GraphQLResponse<T> = await response.json();

    if (result.errors && result.errors.length > 0) {
      throw new Error(result.errors.map((error) => error.message).join('; '));
    }

    if (!result.data) {
      throw new Error('GraphQL returned no data and no errors');
    }

    return result.data;
  } catch (error) {
    if (controller?.signal.aborted) {
      throw new Error(
        'The order request timed out. Check Order History before trying again; the order may still have completed.'
      );
    }
    throw error;
  } finally {
    if (timeoutId !== undefined) window.clearTimeout(timeoutId);
  }
}

// Queries
export const PRODUCTS_QUERY = `
  query GetProducts {
    products {
      id
      sku
      name
      description
      price
      status
      imageUrl
      category
      rating
      reviewCount
      isBestSeller
    }
  }
`;

export const INVENTORIES_QUERY = `
  query GetInventories {
    inventories {
      id
      sku
      quantity
      isInStock
    }
  }
`;

export const ORDERS_QUERY = `
  query GetOrders {
    orders {
      id
      orderNumber
      userId
      username
      orderStatus
      customerName
      customerEmail
      shippingAddress
      city
      postalCode
      phone
      deliveryMethod
      trackingNumber
      carrier
      subtotalAmount
      shippingFee
      taxAmount
      totalAmount
      paymentMethod
      orderItems {
        id
        sku
        price
        quantity
      }
    }
  }
`;

// Mutations
export const PLACE_ORDER_MUTATION = `
  mutation PlaceOrder($input: PlaceOrderInput!) {
    placeOrder(input: $input) {
      id
      orderNumber
      orderStatus
      customerName
      customerEmail
      trackingNumber
      carrier
      totalAmount
      paymentMethod
      orderItems {
        sku
        quantity
        price
      }
    }
  }
`;

export const CANCEL_ORDER_MUTATION = `
  mutation CancelOrder($id: ID!) {
    cancelOrder(id: $id) {
      id
      orderNumber
      orderStatus
    }
  }
`;

export const SHIP_ORDER_MUTATION = `
  mutation ShipOrder($id: ID!) {
    shipOrder(id: $id) {
      id
      orderNumber
      orderStatus
      trackingNumber
      carrier
    }
  }
`;

export const DELIVER_ORDER_MUTATION = `
  mutation DeliverOrder($id: ID!) {
    deliverOrder(id: $id) {
      id
      orderNumber
      orderStatus
      trackingNumber
      carrier
    }
  }
`;

export async function fetchProducts(token?: string): Promise<Product[]> {
  try {
    const [productsData, inventoriesData] = await Promise.all([
      executeGraphQL<{ products: Product[] }>(PRODUCTS_QUERY, {}, token),
      executeGraphQL<{ inventories: InventoryItem[] }>(INVENTORIES_QUERY, {}, token),
    ]);

    const invMap = new Map((inventoriesData.inventories || []).map((i) => [i.sku, i]));
    return (productsData.products || []).map((p) => {
      const inv = invMap.get(p.sku);
      return {
        ...p,
        quantity: inv?.quantity ?? 0,
        isInStock: inv?.isInStock ?? false,
      };
    });
  } catch (err) {
    console.error('Failed to fetch federated products:', err);
    throw err;
  }
}

export async function fetchInventories(token?: string): Promise<InventoryItem[]> {
  const data = await executeGraphQL<{ inventories: InventoryItem[] }>(INVENTORIES_QUERY, {}, token);
  return data.inventories;
}

export async function fetchOrders(token?: string): Promise<Order[]> {
  const accessToken = await getValidAccessToken(token);
  if (!accessToken) {
    throw new Error('Your sign-in session is unavailable. Sign in again to view orders.');
  }

  const data = await executeGraphQL<{ orders: Order[] }>(ORDERS_QUERY, {}, accessToken);
  return data.orders;
}

export async function submitPlaceOrder(
  input: PlaceOrderInput,
  token?: string,
  idempotencyKey?: string
): Promise<Order> {
  const data = await executeGraphQL<{ placeOrder: Order }>(
    PLACE_ORDER_MUTATION,
    { input },
    token,
    idempotencyKey,
    45_000
  );
  return data.placeOrder;
}

export async function submitCancelOrder(id: string, token?: string): Promise<Order> {
  const data = await executeGraphQL<{ cancelOrder: Order }>(CANCEL_ORDER_MUTATION, { id }, token);
  return data.cancelOrder;
}

export async function submitShipOrder(id: string, token?: string): Promise<Order> {
  const data = await executeGraphQL<{ shipOrder: Order }>(SHIP_ORDER_MUTATION, { id }, token);
  return data.shipOrder;
}

export async function submitDeliverOrder(id: string, token?: string): Promise<Order> {
  const data = await executeGraphQL<{ deliverOrder: Order }>(DELIVER_ORDER_MUTATION, { id }, token);
  return data.deliverOrder;
}
