import { Component, OnInit, OnDestroy, ChangeDetectionStrategy, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, Router } from '@angular/router';
import { OrderService } from '../../core/services/order.service';
import { CartStore } from '../../core/services/cart.store';
import { ToastService } from '../../core/services/toast.service';
import { OrderResponse } from '../../core/models/order.model';
import { OrderStepperComponent } from '../../shared/components/order-stepper/order-stepper.component';
import { ReceiptModalComponent } from '../../shared/components/receipt-modal/receipt-modal.component';
import { KeycloakService } from '../../core/auth/keycloak.service';
import { ProductService } from '../../core/services/product.service';
import { getProductImageUrl } from '../../core/utils/product-image.helper';

type OrderFilterTab = 'PROCESSING' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED' | 'ALL';

@Component({
  selector: 'app-order-list',
  standalone: true,
  imports: [CommonModule, RouterModule, OrderStepperComponent, ReceiptModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './order-list.component.html',
  styleUrl: './order-list.component.css'
})
export class OrderListComponent implements OnInit, OnDestroy {
  private readonly orderService = inject(OrderService);
  private readonly cartStore = inject(CartStore);
  private readonly toastService = inject(ToastService);
  readonly keycloakService = inject(KeycloakService);
  readonly productService = inject(ProductService);
  readonly getProductImageUrl = getProductImageUrl;
  private readonly router = inject(Router);

  private autoRefreshTimer?: ReturnType<typeof setInterval>;
  private onVisibilityChangeHandler?: () => void;

  readonly orders = signal<OrderResponse[]>([]);
  readonly isLoading = signal<boolean>(true);
  readonly errorMessage = signal<string | null>(null);
  readonly isAuthRequired = signal<boolean>(false);
  readonly cancellingOrderId = signal<number | null>(null);
  readonly selectedTab = signal<OrderFilterTab>('ALL');
  readonly selectedOrderForModal = signal<OrderResponse | null>(null);
  readonly selectedOrderForReceipt = signal<OrderResponse | null>(null);
  readonly pageSize = signal<number>(10);
  readonly currentPage = signal<number>(1);
  readonly orderStages = signal<Record<number, number>>({});

  readonly processingCount = computed(() => 
    this.orders().filter(o => o.orderStatus === 'PLACED' || !o.orderStatus).length
  );

  readonly shippedCount = computed(() => 
    this.orders().filter(o => o.orderStatus === 'SHIPPED').length
  );

  readonly deliveredCount = computed(() => 
    this.orders().filter(o => o.orderStatus === 'DELIVERED').length
  );

  readonly cancelledCount = computed(() => 
    this.orders().filter(o => o.orderStatus === 'CANCELLED').length
  );

  readonly allCount = computed(() => 
    this.orders().length
  );

  readonly filteredOrders = computed(() => {
    const tab = this.selectedTab();
    // Sort descending: highest id first (latest orders on first page, oldest orders on last page)
    const list = [...this.orders()].sort((a, b) => {
      const idA = a.id ?? 0;
      const idB = b.id ?? 0;
      if (idB !== idA) {
        return idB - idA;
      }
      return (b.orderNumber || '').localeCompare(a.orderNumber || '');
    });
    switch (tab) {
      case 'PROCESSING':
        return list.filter(o => o.orderStatus === 'PLACED' || !o.orderStatus);
      case 'SHIPPED':
        return list.filter(o => o.orderStatus === 'SHIPPED');
      case 'DELIVERED':
        return list.filter(o => o.orderStatus === 'DELIVERED');
      case 'CANCELLED':
        return list.filter(o => o.orderStatus === 'CANCELLED');
      default:
        return list;
    }
  });

  readonly totalPages = computed(() => 
    Math.max(1, Math.ceil(this.filteredOrders().length / this.pageSize()))
  );

  readonly visiblePages = computed<(number | string)[]>(() => {
    const total = this.totalPages();
    const current = this.currentPage();

    if (total <= 7) {
      return Array.from({ length: total }, (_, i) => i + 1);
    }

    if (current <= 4) {
      return [1, 2, 3, 4, 5, '...', total];
    }

    if (current >= total - 3) {
      return [1, '...', total - 4, total - 3, total - 2, total - 1, total];
    }

    return [1, '...', current - 1, current, current + 1, '...', total];
  });

  readonly paginatedOrders = computed(() => {
    const page = this.currentPage();
    const size = this.pageSize();
    const start = (page - 1) * size;
    return this.filteredOrders().slice(start, start + size);
  });

  readonly paginationInfo = computed(() => {
    const total = this.filteredOrders().length;
    if (total === 0) return 'Showing 0 orders';
    const start = (this.currentPage() - 1) * this.pageSize() + 1;
    const end = Math.min(start + this.pageSize() - 1, total);
    return `Showing ${start}-${end} of ${total} orders`;
  });

  ngOnInit(): void {
    this.loadOrders(false);
    this.loadCatalog();

    // Continuous auto-sync every 5 seconds
    this.autoRefreshTimer = setInterval(() => {
      if (!document.hidden) {
        this.loadOrders(true);
        this.loadCatalog();
      }
    }, 5000);

    this.onVisibilityChangeHandler = () => {
      if (document.visibilityState === 'visible') {
        this.loadOrders(true);
        this.loadCatalog();
      }
    };
    document.addEventListener('visibilitychange', this.onVisibilityChangeHandler);
  }

  ngOnDestroy(): void {
    if (this.autoRefreshTimer) {
      clearInterval(this.autoRefreshTimer);
    }
    if (this.onVisibilityChangeHandler) {
      document.removeEventListener('visibilitychange', this.onVisibilityChangeHandler);
    }
  }

  setTab(tab: OrderFilterTab): void {
    this.selectedTab.set(tab);
    this.currentPage.set(1);
  }

  setPageSize(size: number): void {
    this.pageSize.set(size);
    this.currentPage.set(1);
  }

  goToPage(page: number): void {
    if (page >= 1 && page <= this.totalPages()) {
      this.currentPage.set(page);
    }
  }

  goToFirstPage(): void {
    this.goToPage(1);
  }

  goToLastPage(): void {
    this.goToPage(this.totalPages());
  }

  nextPage(): void {
    if (this.currentPage() < this.totalPages()) {
      this.currentPage.update(p => p + 1);
    }
  }

  prevPage(): void {
    if (this.currentPage() > 1) {
      this.currentPage.update(p => p - 1);
    }
  }

  onJumpPage(event: Event): void {
    const input = event.target as HTMLInputElement;
    const pageNum = parseInt(input.value, 10);
    if (!isNaN(pageNum) && pageNum >= 1 && pageNum <= this.totalPages()) {
      this.goToPage(pageNum);
      input.value = '';
    } else {
      input.value = '';
    }
  }

  isNumber(val: number | string): val is number {
    return typeof val === 'number';
  }

  getPageArray(): (number | string)[] {
    return this.visiblePages();
  }

  loadOrders(silent = false): void {
    if (!this.keycloakService.isAuthenticated()) {
      if (!silent) {
        this.isLoading.set(false);
        this.isAuthRequired.set(true);
        this.errorMessage.set(null);
      }
      return;
    }

    if (!silent) {
      this.isLoading.set(true);
      this.errorMessage.set(null);
      this.isAuthRequired.set(false);
    }

    this.orderService.getOrders().subscribe({
      next: (data) => {
        const sorted = [...data].sort((a, b) => {
          const idA = a.id ?? 0;
          const idB = b.id ?? 0;
          if (idB !== idA) {
            return idB - idA;
          }
          return (b.orderNumber || '').localeCompare(a.orderNumber || '');
        });
        this.orders.set(sorted);
        this.isLoading.set(false);
        this.isAuthRequired.set(false);
      },
      error: (err) => {
        if (!silent) {
          this.isLoading.set(false);
          if (err.status === 401 || err.status === 403) {
            this.isAuthRequired.set(true);
            this.keycloakService.isAuthenticated.set(false);
            this.errorMessage.set('Your session has expired. Please sign in again to view your order history.');
          } else {
            this.isAuthRequired.set(false);
            this.errorMessage.set(err?.error?.message || 'Failed to load order history from Orders Service.');
          }
        }
        console.error(err);
      }
    });
  }

  login(): void {
    this.keycloakService.login();
  }

  cancelOrder(order: OrderResponse): void {
    if (this.isCancelDisabled(order)) {
      this.toastService.warning('Cannot Cancel Order', this.getCancelTooltip(order));
      return;
    }

    const confirmed = confirm(`Are you sure you want to cancel Order #${order.orderNumber}? The stock will be restored to inventory.`);
    if (!confirmed) return;

    this.cancellingOrderId.set(order.id || null);
    this.orderService.cancelOrder(order.id!).subscribe({
      next: () => {
        this.orders.update(list => list.map(o => o.id === order.id ? { ...o, orderStatus: 'CANCELLED' } : o));
        this.cancellingOrderId.set(null);
        this.toastService.info('Order Cancelled', `Order #${order.orderNumber} cancelled and stock returned.`);
      },
      error: (err) => {
        this.cancellingOrderId.set(null);
        this.toastService.error('Cancellation Failed', err.error?.message || 'Could not cancel order.');
      }
    });
  }

  getOrderStage(order: OrderResponse): number {
    if (order.orderStatus === 'CANCELLED') return 0;
    if (order.orderStatus === 'DELIVERED') return 5;
    if (order.orderStatus === 'SHIPPED') return 3;
    if (order.id && this.orderStages()[order.id] !== undefined) {
      return this.orderStages()[order.id];
    }
    return 1; // Default for PLACED orders is Stage 1: Placed
  }

  isCancelDisabled(order: OrderResponse): boolean {
    if (this.cancellingOrderId() === order.id) return true;
    if (!order.id || order.orderStatus === 'CANCELLED') return true;
    if (order.orderStatus === 'SHIPPED' || order.orderStatus === 'DELIVERED') return true;
    const stage = this.getOrderStage(order);
    return stage >= 2; // Locked from Stage 2 (Preparing) through Delivered (Stage 5)
  }

  getCancelTooltip(order: OrderResponse): string {
    if (order.orderStatus === 'CANCELLED') {
      return 'Order is already cancelled.';
    }
    if (order.orderStatus === 'DELIVERED' || this.getOrderStage(order) === 5) {
      return 'Cannot cancel: Package has already been delivered to destination.';
    }
    if (order.orderStatus === 'SHIPPED' || this.getOrderStage(order) >= 3) {
      return 'Cannot cancel: Order is already in transit with delivery carrier.';
    }
    if (this.getOrderStage(order) === 2) {
      return 'Cannot cancel: Order is being prepared and packed at fulfillment center.';
    }
    return 'Cancel Order (Restores inventory via Saga compensation)';
  }

  reorder(order: OrderResponse): void {
    if (!order.orderItems || order.orderItems.length === 0) return;

    order.orderItems.forEach(item => {
      this.cartStore.addToCart({
        id: item.id || 0,
        sku: item.sku,
        name: item.sku,
        description: 'Re-ordered product from past purchase',
        price: item.price,
        status: true
      }, item.quantity);
    });

    this.toastService.success('Items Added to Cart', `${order.orderItems.length} product(s) copied from Order #${order.orderNumber}.`);
    this.cartStore.toggleCart(true);
  }

  shipOrder(order: OrderResponse): void {
    if (!order.id) return;
    this.orderService.shipOrder(order.id).subscribe({
      next: (updated) => {
        this.orders.update(list => list.map(o => o.id === order.id ? updated : o));
        this.toastService.success('Order Dispatched', `Order #${order.orderNumber} marked as SHIPPED.`);
      },
      error: (err) => {
        this.toastService.error('Failed to Ship Order', err.error?.message || 'Could not update status.');
      }
    });
  }

  deliverOrder(order: OrderResponse): void {
    if (!order.id) return;
    this.orderService.deliverOrder(order.id).subscribe({
      next: (updated) => {
        this.orders.update(list => list.map(o => o.id === order.id ? updated : o));
        this.toastService.success('Order Delivered', `Order #${order.orderNumber} marked as DELIVERED.`);
      },
      error: (err) => {
        this.toastService.error('Failed to Deliver Order', err.error?.message || 'Could not update status.');
      }
    });
  }

  onOrderStatusUpdated(event: { orderId?: number; status: 'PLACED' | 'CANCELLED' | 'SHIPPED' | 'DELIVERED' }): void {
    if (event.orderId) {
      this.orders.update(list =>
        list.map(o => o.id === event.orderId ? { ...o, orderStatus: event.status } : o)
      );
    }
  }

  onOrderStageUpdated(event: { orderId?: number; stage: number; stageName: string }): void {
    if (event.orderId) {
      this.orderStages.update(map => ({
        ...map,
        [event.orderId!]: event.stage
      }));
    }
  }

  openReceipt(order: OrderResponse): void {
    this.selectedOrderForReceipt.set(order);
  }

  closeReceipt(): void {
    this.selectedOrderForReceipt.set(null);
  }

  getStatusClass(status?: string): string {
    switch (status) {
      case 'CANCELLED':
        return 'status-cancelled';
      case 'SHIPPED':
      case 'DELIVERED':
        return 'status-shipped';
      default:
        return 'status-placed';
    }
  }

  getStatusLabel(status?: string): string {
    switch (status) {
      case 'PLACED':
        return 'Confirmed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'SHIPPED':
        return 'Shipped';
      case 'DELIVERED':
        return 'Delivered';
      default:
        return 'Placed';
    }
  }

  calculateOrderTotal(order: OrderResponse): number {
    if (!order.orderItems) return 0;
    return order.orderItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  }

  openDetailsModal(order: OrderResponse): void {
    this.selectedOrderForModal.set(order);
  }

  closeDetailsModal(): void {
    this.selectedOrderForModal.set(null);
  }

  loadCatalog(): void {
    this.productService.getProducts().subscribe({
      error: () => {} // Handled silently with local persistent fallback
    });
  }

  getItemImageUrl(sku: string): string {
    return this.productService.getProductImage(sku);
  }

  getItemName(sku: string): string {
    return this.productService.getProductName(sku);
  }

  onImageError(event: Event, sku: string): void {
    const img = event.target as HTMLImageElement;
    if (img) {
      img.src = getProductImageUrl({ sku });
    }
  }

  getTracingUrl(): string {
    const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
    return `http://${host}:3000/explore?schemaVersion=1&panes=%7B%22tempo-pane%22:%7B%22datasource%22:%22tempo-ds%22,%22queries%22:%5B%7B%22refId%22:%22A%22,%22datasource%22:%7B%22type%22:%22tempo%22,%22uid%22:%22tempo-ds%22%7D,%22queryType%22:%22search%22,%22serviceName%22:%22orders-service%22%7D%5D%7D%7D&orgId=1`;
  }
}
