import { Component, OnInit, OnDestroy, ChangeDetectionStrategy, computed, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
import { ProductService } from '../../core/services/product.service';
import { InventoryService } from '../../core/services/inventory.service';
import { OrderService } from '../../core/services/order.service';
import { ToastService } from '../../core/services/toast.service';
import { NotificationCenterService } from '../../core/services/notification-center.service';
import { ProductResponse } from '../../core/models/product.model';
import { InventoryResponse } from '../../core/models/inventory.model';
import { OrderResponse } from '../../core/models/order.model';
import { PRODUCT_IMAGE_PRESETS, ProductImagePreset, compressImageFile, getProductImageUrl } from '../../core/utils/product-image.helper';

import { SystemStatusComponent } from '../status/system-status.component';
import { SystemStatusService } from '../../core/services/system-status.service';

@Component({
  selector: 'app-admin-dashboard',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule, FormsModule, SystemStatusComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './admin-dashboard.component.html',
  styleUrl: './admin-dashboard.component.css'
})
export class AdminDashboardComponent implements OnInit, OnDestroy {
  private readonly fb = inject(FormBuilder);
  private readonly productService = inject(ProductService);
  private readonly inventoryService = inject(InventoryService);
  private readonly orderService = inject(OrderService);
  private readonly toastService = inject(ToastService);
  private readonly notifService = inject(NotificationCenterService);
  readonly statusService = inject(SystemStatusService);
  private autoRefreshTimer?: ReturnType<typeof setInterval>;

  readonly activeTab = signal<'products' | 'inventory' | 'orders' | 'system'>('products');
  readonly isRefreshingProducts = signal<boolean>(false);
  readonly isRefreshingInventory = signal<boolean>(false);

  readonly onlineServicesCount = computed(() =>
    this.statusService.services().filter(s => s.status === 'UP').length
  );
  readonly totalServicesCount = computed(() => this.statusService.services().length);
  readonly isClusterHealthy = computed(() =>
    this.totalServicesCount() > 0 && this.onlineServicesCount() === this.totalServicesCount()
  );

  // Product Data & Image Handling
  readonly existingProducts = signal<ProductResponse[]>([]);
  readonly isSubmittingProduct = signal<boolean>(false);
  readonly editingProductId = signal<number | null>(null);
  readonly productFilter = signal<string>('');
  readonly isCompressingImage = signal<boolean>(false);
  readonly imagePresets = PRODUCT_IMAGE_PRESETS;
  readonly getProductImageUrl = getProductImageUrl;

  // Inventory Data
  readonly existingInventory = signal<InventoryResponse[]>([]);
  readonly isSubmittingInventory = signal<boolean>(false);
  readonly inventoryFilter = signal<string>('');

  // Orders Data
  readonly existingOrders = signal<OrderResponse[]>([]);
  readonly isOrdersLoading = signal<boolean>(false);
  readonly ordersFilter = signal<string>('');
  readonly ordersStatusFilter = signal<'ALL' | 'PLACED' | 'CANCELLED'>('ALL');
  readonly cancellingOrderId = signal<number | null>(null);

  // Regular expressions synchronized with Backend (Jakarta Validation)
  readonly SKU_REGEX = /^[A-Z0-9-]{6,20}$/;
  readonly NAME_REGEX = /^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9.,'() -]{3,150}$/;
  readonly PRICE_REGEX = /^\d+(\.\d{1,2})?$/;

  productForm: FormGroup = this.fb.group({
    sku: ['', [Validators.required, Validators.pattern(this.SKU_REGEX)]],
    name: ['', [Validators.required, Validators.pattern(this.NAME_REGEX)]],
    description: ['', [Validators.required, Validators.minLength(5), Validators.maxLength(2000)]],
    price: [null, [Validators.required, Validators.min(0.01)]],
    initialStock: [25, [Validators.required, Validators.min(0)]],
    imageUrl: [''],
    status: [true]
  });

  async onFileSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    if (!input.files || input.files.length === 0) return;

    const file = input.files[0];
    this.isCompressingImage.set(true);
    try {
      const compressedDataUrl = await compressImageFile(file, 800, 0.82);
      this.productForm.patchValue({ imageUrl: compressedDataUrl });
      this.toastService.success('Image Processed', `Compressed & ready for storage (${Math.round(compressedDataUrl.length / 1024)} KB)`);
    } catch (err: any) {
      console.error('Image compression error:', err);
      this.toastService.error('Upload Failed', err?.message || 'Unable to process local image file.');
    } finally {
      this.isCompressingImage.set(false);
      input.value = '';
    }
  }

  applyImagePreset(preset: ProductImagePreset): void {
    this.productForm.patchValue({ imageUrl: preset.url });
    this.toastService.info('Preset Selected', `Applied image for ${preset.label}`);
  }

  clearImage(): void {
    this.productForm.patchValue({ imageUrl: '' });
  }

  readonly filteredTableProducts = computed(() => {
    const q = this.productFilter().toLowerCase().trim();
    const list = this.existingProducts();
    if (!q) return list;
    return list.filter(p =>
      p.name.toLowerCase().includes(q) ||
      p.sku.toLowerCase().includes(q) ||
      p.id?.toString().includes(q)
    );
  });

  readonly filteredTableInventory = computed(() => {
    const q = this.inventoryFilter().toLowerCase().trim();
    const list = this.existingInventory();
    if (!q) return list;
    return list.filter(inv => inv.sku.toLowerCase().includes(q));
  });

  readonly totalRevenue = computed(() => {
    return this.existingOrders()
      .filter(o => o.orderStatus !== 'CANCELLED')
      .reduce((sum, order) => sum + this.calculateOrderTotal(order), 0);
  });

  readonly activeOrdersCount = computed(() => {
    return this.existingOrders().filter(o => o.orderStatus !== 'CANCELLED').length;
  });

  readonly cancelledOrdersCount = computed(() => {
    return this.existingOrders().filter(o => o.orderStatus === 'CANCELLED').length;
  });

  readonly refundedAmount = computed(() => {
    return this.existingOrders()
      .filter(o => o.orderStatus === 'CANCELLED')
      .reduce((sum, order) => sum + this.calculateOrderTotal(order), 0);
  });

  readonly filteredTableOrders = computed(() => {
    const q = this.ordersFilter().toLowerCase().trim();
    const status = this.ordersStatusFilter();
    let list = this.existingOrders();

    if (status === 'PLACED') {
      list = list.filter(o => o.orderStatus !== 'CANCELLED');
    } else if (status === 'CANCELLED') {
      list = list.filter(o => o.orderStatus === 'CANCELLED');
    }

    if (!q) return list;
    return list.filter(o =>
      o.orderNumber?.toLowerCase().includes(q) ||
      o.id?.toString().includes(q) ||
      o.orderItems?.some(i => i.sku.toLowerCase().includes(q))
    );
  });

  // Products Pagination
  readonly productsPage = signal<number>(1);
  readonly productsPageSize = signal<number>(10);

  readonly productsTotalPages = computed(() =>
    Math.max(1, Math.ceil(this.filteredTableProducts().length / this.productsPageSize()))
  );

  readonly paginatedProducts = computed(() => {
    const list = this.filteredTableProducts();
    const page = this.productsPage();
    const size = this.productsPageSize();
    const start = (page - 1) * size;
    return list.slice(start, start + size);
  });

  readonly productsVisiblePages = computed<(number | string)[]>(() =>
    this.calculateVisiblePages(this.productsPage(), this.productsTotalPages())
  );

  readonly productsPaginationInfo = computed(() => {
    const total = this.filteredTableProducts().length;
    if (total === 0) return 'Showing 0 products';
    const start = (this.productsPage() - 1) * this.productsPageSize() + 1;
    const end = Math.min(start + this.productsPageSize() - 1, total);
    return `Showing ${start}-${end} of ${total} products`;
  });

  // Inventory Pagination
  readonly inventoryPage = signal<number>(1);
  readonly inventoryPageSize = signal<number>(10);

  readonly inventoryTotalPages = computed(() =>
    Math.max(1, Math.ceil(this.filteredTableInventory().length / this.inventoryPageSize()))
  );

  readonly paginatedInventory = computed(() => {
    const list = this.filteredTableInventory();
    const page = this.inventoryPage();
    const size = this.inventoryPageSize();
    const start = (page - 1) * size;
    return list.slice(start, start + size);
  });

  readonly inventoryVisiblePages = computed<(number | string)[]>(() =>
    this.calculateVisiblePages(this.inventoryPage(), this.inventoryTotalPages())
  );

  readonly inventoryPaginationInfo = computed(() => {
    const total = this.filteredTableInventory().length;
    if (total === 0) return 'Showing 0 items';
    const start = (this.inventoryPage() - 1) * this.inventoryPageSize() + 1;
    const end = Math.min(start + this.inventoryPageSize() - 1, total);
    return `Showing ${start}-${end} of ${total} items`;
  });

  // Orders Pagination
  readonly ordersPage = signal<number>(1);
  readonly ordersPageSize = signal<number>(10);

  readonly ordersTotalPages = computed(() =>
    Math.max(1, Math.ceil(this.filteredTableOrders().length / this.ordersPageSize()))
  );

  readonly paginatedOrders = computed(() => {
    const list = this.filteredTableOrders();
    const page = this.ordersPage();
    const size = this.ordersPageSize();
    const start = (page - 1) * size;
    return list.slice(start, start + size);
  });

  readonly ordersVisiblePages = computed<(number | string)[]>(() =>
    this.calculateVisiblePages(this.ordersPage(), this.ordersTotalPages())
  );

  readonly ordersPaginationInfo = computed(() => {
    const total = this.filteredTableOrders().length;
    if (total === 0) return 'Showing 0 orders';
    const start = (this.ordersPage() - 1) * this.ordersPageSize() + 1;
    const end = Math.min(start + this.ordersPageSize() - 1, total);
    return `Showing ${start}-${end} of ${total} orders`;
  });

  readonly HARDWARE_PRESETS = [
    { name: 'Apple Vision Pro', sku: 'SKU-VISION-PRO', price: 3499.00, initialStock: 20, desc: 'Spatial computer blending digital media with the real world' },
    { name: 'PlayStation 5 Pro', sku: 'SKU-PS5-PRO-2TB', price: 699.99, initialStock: 45, desc: 'Enhanced 4K gaming at 60fps with advanced ray tracing' },
    { name: 'NVIDIA RTX 4090 OC', sku: 'SKU-RTX-4090-24GB', price: 1899.99, initialStock: 15, desc: 'Ada Lovelace architecture, 24GB G6X memory, DLSS 3.5' },
    { name: 'Dell XPS 16 OLED', sku: 'SKU-DELL-XPS-16', price: 2799.00, initialStock: 30, desc: 'Intel Core Ultra 9, 32GB RAM, 4K OLED Touch Display' },
    { name: 'Bose QC Ultra Headphones', sku: 'SKU-BOSE-QC-ULTRA', price: 429.00, initialStock: 60, desc: 'World-class active noise cancellation with spatial audio' }
  ];

  applyPreset(preset: any): void {
    this.productForm.patchValue({
      sku: preset.sku,
      name: preset.name,
      description: preset.desc,
      price: preset.price,
      initialStock: preset.initialStock ?? 25,
      status: true
    });
    this.toastService.info('Preset Applied', `Loaded template for ${preset.name} (${preset.initialStock} units)`);
  }

  getProductName(sku: string): string {
    const found = this.existingProducts().find(p => p.sku.toUpperCase() === sku.toUpperCase());
    return found ? found.name : sku;
  }

  selectProductSku(sku: string): void {
    const inv = this.existingInventory().find(i => i.sku.toUpperCase() === sku.toUpperCase());
    this.inventoryForm.patchValue({
      sku: sku,
      quantity: inv ? inv.quantity : 25
    });
    this.toastService.info('Product Selected', `Loaded inventory stock for SKU ${sku}`);
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  inventoryForm: FormGroup = this.fb.group({
    sku: ['', [Validators.required, Validators.pattern(this.SKU_REGEX)]],
    quantity: [25, [Validators.required, Validators.min(0)]]
  });

  ngOnInit(): void {
    this.loadProducts();
    this.loadInventory();
    this.loadOrders();
    this.statusService.checkAllServices();

    // Dynamic continuous sync in background every 4 seconds
    this.autoRefreshTimer = setInterval(() => {
      if (!document.hidden) {
        this.loadProducts();
        this.loadInventory();
        this.loadOrders(true);
      }
    }, 4000);
  }

  ngOnDestroy(): void {
    if (this.autoRefreshTimer) {
      clearInterval(this.autoRefreshTimer);
    }
  }

  loadProducts(manual = false): void {
    if (manual) {
      this.isRefreshingProducts.set(true);
    }
    this.productService.getProducts().subscribe({
      next: (data) => {
        this.existingProducts.set(data);
        if (manual) {
          setTimeout(() => this.isRefreshingProducts.set(false), 500);
          this.toastService.info('Catalog Synchronized', 'Real-time product inventory refreshed.');
        }
      },
      error: (err) => {
        if (manual) this.isRefreshingProducts.set(false);
        console.error('Error loading products:', err);
      }
    });
  }

  loadInventory(manual = false): void {
    if (manual) {
      this.isRefreshingInventory.set(true);
    }
    this.inventoryService.getAllInventory().subscribe({
      next: (data) => {
        this.existingInventory.set(data);
        if (manual) {
          setTimeout(() => this.isRefreshingInventory.set(false), 500);
          this.toastService.info('Inventory Synchronized', 'Real-time warehouse stock refreshed.');
        }
      },
      error: (err) => {
        if (manual) this.isRefreshingInventory.set(false);
        console.error('Error loading inventory:', err);
      }
    });
  }

  loadOrders(silent = false): void {
    if (!silent) {
      this.isOrdersLoading.set(true);
    }
    this.orderService.getOrders().subscribe({
      next: (data) => {
        this.existingOrders.set(data);
        this.isOrdersLoading.set(false);
      },
      error: (err) => {
        this.isOrdersLoading.set(false);
        console.error('Error loading orders:', err);
      }
    });
  }

  adminCancelOrder(order: OrderResponse): void {
    if (!order.id || order.orderStatus !== 'PLACED') {
      this.toastService.warning('Cannot Cancel', `Order #${order.orderNumber} cannot be cancelled because it is in status ${order.orderStatus}.`);
      return;
    }

    const confirmed = window.confirm(`Admin Confirmation: Are you sure you want to cancel Order #${order.orderNumber}? Reserved stock will be returned to inventory via Saga compensation.`);
    if (!confirmed) return;

    this.cancellingOrderId.set(order.id);
    this.orderService.cancelOrder(order.id).subscribe({
      next: () => {
        this.cancellingOrderId.set(null);
        this.toastService.success('Order Cancelled', `Order #${order.orderNumber} cancelled. Stock restored.`);
        this.notifService.addNotification({
          title: 'Order Cancelled (Admin)',
          message: `Order #${order.orderNumber} was cancelled and stock restored to inventory.`,
          type: 'warning'
        });
        this.loadOrders();
        this.loadInventory();
      },
      error: (err) => {
        this.cancellingOrderId.set(null);
        console.error('Admin order cancel error:', err);
        this.toastService.error('Cancel Failed', err?.error?.message || 'Unable to cancel order.');
      }
    });
  }

  getOrderStatusClass(status?: string): string {
    switch (status) {
      case 'CANCELLED':
        return 'status-tag-cancelled';
      case 'SHIPPED':
      case 'DELIVERED':
        return 'status-tag-shipped';
      default:
        return 'status-tag-placed';
    }
  }

  calculateOrderTotal(order: OrderResponse): number {
    if (!order.orderItems) return 0;
    return order.orderItems.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  }

  isFieldInvalid(field: string): boolean {
    const control = this.productForm.get(field);
    return !!(control && control.invalid && (control.dirty || control.touched));
  }

  isFieldValid(field: string): boolean {
    const control = this.productForm.get(field);
    return !!(control && control.valid && (control.dirty || control.touched));
  }

  onSkuInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    if (input?.value) {
      const upper = input.value.toUpperCase();
      this.productForm.get('sku')?.setValue(upper, { emitEvent: false });
    }
  }

  editProduct(product: ProductResponse): void {
    if (!product.id) return;
    this.editingProductId.set(product.id);
    const usd = product.price || 0;
    const inv = this.existingInventory().find(i => i.sku.toUpperCase() === product.sku.toUpperCase());
    const currentStock = inv ? inv.quantity : 0;
    this.productForm.patchValue({
      sku: product.sku,
      name: product.name,
      description: product.description,
      price: usd,
      initialStock: currentStock,
      imageUrl: product.imageUrl || '',
      status: product.status
    });
    this.productForm.markAsTouched();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  cancelEditProduct(): void {
    this.editingProductId.set(null);
    this.productForm.reset({ status: true, initialStock: 25, imageUrl: '' });
  }

  deleteProduct(product: ProductResponse): void {
    if (!product.id) return;
    const confirmDelete = window.confirm(`Are you sure you want to delete product "${product.name}" (SKU: ${product.sku})?`);
    if (!confirmDelete) return;

    this.productService.deleteProduct(product.id).subscribe({
      next: () => {
        this.toastService.success('Product Deleted', `Product ${product.name} (SKU: ${product.sku}) was removed.`);
        if (this.editingProductId() === product.id) {
          this.cancelEditProduct();
        }
        this.loadProducts();
      },
      error: (err) => {
        console.error('Error deleting product:', err);
        this.toastService.error('Delete Failed', err?.error?.message || 'Unable to delete product.');
      }
    });
  }

  onSubmitProduct(): void {
    if (this.productForm.invalid) return;

    this.isSubmittingProduct.set(true);
    const formValue = this.productForm.value;
    const priceUsd = Number(formValue.price);
    const stockQty = Number(formValue.initialStock !== null && formValue.initialStock !== undefined ? formValue.initialStock : 25);

    const payload = {
      sku: formValue.sku.toUpperCase().trim(),
      name: formValue.name.trim(),
      description: formValue.description.trim(),
      price: priceUsd,
      imageUrl: formValue.imageUrl?.trim() || undefined,
      status: !!formValue.status
    };

    const isEdit = this.editingProductId() !== null;
    const request$ = isEdit
      ? this.productService.updateProduct(this.editingProductId()!, payload)
      : this.productService.createProduct(payload);

    request$.subscribe({
      next: () => {
        // Automatically synchronize inventory stock in inventory-service
        this.inventoryService.saveOrUpdateStock({
          sku: payload.sku,
          quantity: stockQty
        }).subscribe({
          next: () => {
            this.isSubmittingProduct.set(false);
            const action = isEdit ? 'Updated' : 'Created';
            this.toastService.success(`Product ${action} & Stock Initialized`, `Product ${payload.name} saved with ${stockQty} units in inventory.`);
            this.notifService.addNotification({
              title: `Product & Stock ${action}`,
              message: `SKU ${payload.sku} (${payload.name}) is registered and active with ${stockQty} units.`,
              type: 'success'
            });
            this.cancelEditProduct();
            this.loadProducts();
            this.loadInventory();
          },
          error: (invErr) => {
            this.isSubmittingProduct.set(false);
            const action = isEdit ? 'Updated' : 'Created';
            this.toastService.warning(`Product ${action}`, `Product saved, but stock update had a notice: ${invErr?.message || ''}`);
            this.cancelEditProduct();
            this.loadProducts();
            this.loadInventory();
          }
        });
      },
      error: (err: any) => {
        this.isSubmittingProduct.set(false);
        console.error('Error saving product:', err);
        let errorMsg = 'Unable to persist product.';
        if (err?.error?.message) {
          errorMsg = err.error.message;
        } else if (err?.error?.fields) {
          errorMsg = Object.entries(err.error.fields).map(([k, v]) => `${k}: ${v}`).join(' | ');
        } else if (err?.error?.error) {
          errorMsg = err.error.error;
        }
        this.toastService.error('Save Failed', errorMsg);
      }
    });
  }

  // Inventory Management Methods
  selectSkuForInventory(inv: InventoryResponse): void {
    this.inventoryForm.patchValue({
      sku: inv.sku,
      quantity: inv.quantity
    });
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  adjustQuantityInput(amount: number): void {
    const current = Number(this.inventoryForm.get('quantity')?.value || 0);
    this.inventoryForm.patchValue({ quantity: Math.max(0, current + amount) });
  }

  adjustQuickQuantity(amount: number): void {
    this.adjustQuantityInput(amount);
  }

  quickChangeStock(sku: string, newQuantity: number): void {
    const safeQty = Math.max(0, newQuantity);
    this.inventoryService.updateStock(sku, safeQty).subscribe({
      next: () => {
        this.toastService.success('Stock Updated', `SKU ${sku}: ${safeQty} units.`);
        this.notifService.addNotification({
          title: 'Stock Updated',
          message: `Inventory stock for ${sku} updated to ${safeQty} units.`,
          type: 'info'
        });
        this.loadInventory();
      },
      error: (err) => {
        console.error('Error adjusting stock:', err);
        this.toastService.error('Stock Update Failed', 'Unable to update inventory levels.');
      }
    });
  }

  onSubmitInventory(): void {
    if (this.inventoryForm.invalid) return;

    this.isSubmittingInventory.set(true);
    const val = this.inventoryForm.value;
    const payload = {
      sku: val.sku.toUpperCase().trim(),
      quantity: Number(val.quantity)
    };

    this.inventoryService.saveOrUpdateStock(payload).subscribe({
      next: () => {
        this.isSubmittingInventory.set(false);
        this.toastService.success('Inventory Saved', `SKU ${payload.sku} updated to ${payload.quantity} units.`);
        this.notifService.addNotification({
          title: 'Inventory Saved',
          message: `SKU ${payload.sku} updated to ${payload.quantity} units.`,
          type: 'success'
        });
        this.loadInventory();
      },
      error: (err) => {
        this.isSubmittingInventory.set(false);
        console.error('Error saving inventory:', err);
        this.toastService.error('Inventory Save Failed', err?.error?.message || 'Unable to persist stock allocation.');
      }
    });
  }

  isNumber(val: number | string): val is number {
    return typeof val === 'number';
  }

  private calculateVisiblePages(current: number, total: number): (number | string)[] {
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
  }

  // Products Pagination Handlers
  setProductsPage(page: number): void {
    if (page >= 1 && page <= this.productsTotalPages()) {
      this.productsPage.set(page);
    }
  }

  setProductsPageSize(size: number): void {
    this.productsPageSize.set(size);
    this.productsPage.set(1);
  }

  onProductsJumpPage(event: Event): void {
    const input = event.target as HTMLInputElement;
    const p = parseInt(input.value, 10);
    if (!isNaN(p) && p >= 1 && p <= this.productsTotalPages()) {
      this.productsPage.set(p);
      input.value = '';
    } else {
      input.value = '';
    }
  }

  // Inventory Pagination Handlers
  setInventoryPage(page: number): void {
    if (page >= 1 && page <= this.inventoryTotalPages()) {
      this.inventoryPage.set(page);
    }
  }

  setInventoryPageSize(size: number): void {
    this.inventoryPageSize.set(size);
    this.inventoryPage.set(1);
  }

  onInventoryJumpPage(event: Event): void {
    const input = event.target as HTMLInputElement;
    const p = parseInt(input.value, 10);
    if (!isNaN(p) && p >= 1 && p <= this.inventoryTotalPages()) {
      this.inventoryPage.set(p);
      input.value = '';
    } else {
      input.value = '';
    }
  }

  // Orders Pagination Handlers
  setOrdersPage(page: number): void {
    if (page >= 1 && page <= this.ordersTotalPages()) {
      this.ordersPage.set(page);
    }
  }

  setOrdersPageSize(size: number): void {
    this.ordersPageSize.set(size);
    this.ordersPage.set(1);
  }

  onOrdersJumpPage(event: Event): void {
    const input = event.target as HTMLInputElement;
    const p = parseInt(input.value, 10);
    if (!isNaN(p) && p >= 1 && p <= this.ordersTotalPages()) {
      this.ordersPage.set(p);
      input.value = '';
    } else {
      input.value = '';
    }
  }

  onProductFilterChange(query: string): void {
    this.productFilter.set(query);
    this.productsPage.set(1);
  }

  onInventoryFilterChange(query: string): void {
    this.inventoryFilter.set(query);
    this.inventoryPage.set(1);
  }

  onOrdersFilterChange(query: string): void {
    this.ordersFilter.set(query);
    this.ordersPage.set(1);
  }

  onOrdersStatusFilterChange(status: 'ALL' | 'PLACED' | 'CANCELLED'): void {
    this.ordersStatusFilter.set(status);
    this.ordersPage.set(1);
  }
}
