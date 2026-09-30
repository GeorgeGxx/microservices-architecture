/** The storefront permits cancellation only while the backend order remains PLACED. */
export function canCancelOrder(status?: string | null): boolean {
  return status?.trim().toUpperCase() === 'PLACED';
}
