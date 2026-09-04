export interface InventoryResponse {
  id?: number;
  sku: string;
  quantity: number;
}

export interface InventoryRequest {
  sku: string;
  quantity: number;
}
