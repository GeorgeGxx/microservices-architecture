export interface ProductRequest {
  sku: string;
  name: string;
  description: string;
  price: number;
  status: boolean;
  imageUrl?: string;
  category?: string;
  rating?: number;
  reviewCount?: number;
  isBestSeller?: boolean;
  prices?: Record<string, number>;
}

export interface ProductResponse {
  id?: number;
  sku: string;
  name: string;
  description: string;
  price: number;
  status: boolean;
  imageUrl?: string;
  category?: string;
  rating?: number;
  reviewCount?: number;
  isBestSeller?: boolean;
  prices?: Record<string, number>;
}
