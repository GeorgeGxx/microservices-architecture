import { Component, OnInit, OnDestroy, ChangeDetectionStrategy, computed, effect, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ProductService } from '../../core/services/product.service';
import { InventoryService } from '../../core/services/inventory.service';
import { CartStore } from '../../core/services/cart.store';
import { ToastService } from '../../core/services/toast.service';
import { KeycloakService } from '../../core/auth/keycloak.service';
import { ProductResponse } from '../../core/models/product.model';
import { ProductQuickViewModalComponent } from '../../shared/components/quick-view/quick-view-modal.component';
import { ProductQrModalComponent } from '../../shared/components/product-qr-modal/product-qr-modal.component';
import { CurrencyService } from '../../core/services/currency.service';
import { getProductImageUrl } from '../../core/utils/product-image.helper';

export interface ProductWithStock extends ProductResponse {
  inStock?: boolean;
  stockQuantity?: number;
  checkingStock?: boolean;
}

@Component({
  selector: 'app-product-list',
  standalone: true,
  imports: [CommonModule, FormsModule, ProductQuickViewModalComponent, ProductQrModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './product-list.component.html',
  styleUrl: './product-list.component.css'
})
export class ProductListComponent implements OnInit, OnDestroy {
  private readonly productService = inject(ProductService);
  private readonly inventoryService = inject(InventoryService);
  private readonly cartStore = inject(CartStore);
  private readonly toastService = inject(ToastService);
  readonly currencyService = inject(CurrencyService);
  readonly keycloakService = inject(KeycloakService);
  readonly getProductImageUrl = getProductImageUrl;

  onImageError(event: Event, product: ProductWithStock): void {
    const target = event.target as HTMLImageElement;
    if (target) {
      target.src = getProductImageUrl({ sku: product.sku, name: product.name });
    }
  }

  readonly Math = Math;

  readonly products = signal<ProductWithStock[]>([]);
  readonly searchQuery = signal<string>('');
  readonly selectedSort = signal<string>('recent');
  readonly stockFilter = signal<string>('all');
  readonly minPrice = signal<number | null>(null);

  // Product QR Code Modal State
  readonly qrProduct = signal<ProductWithStock | null>(null);
  readonly isQrModalOpen = signal<boolean>(false);
  readonly maxPrice = signal<number | null>(null);

  // Recent Searches
  readonly recentSearches = signal<string[]>(this.getRecentSearches());
  readonly showSearchSuggestions = signal<boolean>(false);

  // Quick View Modal State
  readonly quickViewProduct = signal<ProductWithStock | null>(null);
  readonly isQuickViewOpen = signal<boolean>(false);

  // Pagination
  readonly currentPage = signal<number>(1);
  readonly pageSize = signal<number>(6);

  readonly isLoading = signal<boolean>(false);
  readonly isRefreshing = signal<boolean>(false);
  readonly lastUpdatedText = signal<string>('just now');
  readonly errorMessage = signal<string | null>(null);

  private autoRefreshTimer?: ReturnType<typeof setInterval>;
  private onVisibilityChangeHandler?: () => void;
  private onFocusHandler?: () => void;
  private onProductUpdatedHandler?: () => void;

  readonly hasActiveFilters = computed(() =>
    this.searchQuery().trim() !== '' ||
    this.stockFilter() !== 'all' ||
    this.selectedSort() !== 'recent' ||
    this.minPrice() !== null ||
    this.maxPrice() !== null
  );

  readonly searchSuggestions = computed(() => {
    const q = this.searchQuery().trim().toLowerCase();
    if (!q) return [];
    const isAdmin = this.keycloakService.isAdmin();
    return this.products()
      .filter(p => (isAdmin || p.status !== false) && (p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q)))
      .slice(0, 5);
  });

  readonly filteredProducts = computed(() => {
    const q = this.searchQuery().toLowerCase().trim();
    const sort = this.selectedSort();
    const stock = this.stockFilter();
    const min = this.minPrice();
    const max = this.maxPrice();
    const isAdmin = this.keycloakService.isAdmin();

    let list = this.products().filter(p => {
      // Inactive products are completely hidden from regular customers (basic_user) and guests:
      if (!isAdmin && p.status === false) {
        return false;
      }

      // Search query filter
      const matchesSearch = !q || (
        p.name.toLowerCase().includes(q) ||
        p.sku.toLowerCase().includes(q) ||
        p.description?.toLowerCase().includes(q)
      );

      // Stock status filter
      let matchesStock = true;
      if (stock === 'in-stock') matchesStock = !!p.inStock;
      if (stock === 'out-of-stock') matchesStock = p.inStock === false;

      // Price range filter in active currency
      const activePrice = this.currencyService.getProductPrice(p);
      let matchesMin = min === null || activePrice >= min;
      let matchesMax = max === null || activePrice <= max;

      return matchesSearch && matchesStock && matchesMin && matchesMax;
    });

    // Sorting in active currency
    if (sort === 'price-asc') {
      list = [...list].sort((a, b) => this.currencyService.getProductPrice(a) - this.currencyService.getProductPrice(b));
    } else if (sort === 'price-desc') {
      list = [...list].sort((a, b) => this.currencyService.getProductPrice(b) - this.currencyService.getProductPrice(a));
    } else if (sort === 'name-asc') {
      list = [...list].sort((a, b) => a.name.localeCompare(b.name));
    } else if (sort === 'name-desc') {
      list = [...list].sort((a, b) => b.name.localeCompare(a.name));
    }

    return list;
  });

  readonly totalPages = computed(() => {
    const count = this.filteredProducts().length;
    const size = this.pageSize();
    return Math.max(1, Math.ceil(count / size));
  });

  readonly pageNumbers = computed<(number | string)[]>(() => {
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

  readonly paginatedProducts = computed(() => {
    const list = this.filteredProducts();
    const page = this.currentPage();
    const size = this.pageSize();
    const start = (page - 1) * size;
    return list.slice(start, start + size);
  });

  constructor() {
    // Reset to page 1 whenever any filter criteria changes
    effect(() => {
      this.searchQuery();
      this.selectedSort();
      this.stockFilter();
      this.minPrice();
      this.maxPrice();
      this.currentPage.set(1);
    });
  }

  ngOnInit(): void {
    this.loadProducts(false);

    // Silent auto-sync every 8 seconds
    this.autoRefreshTimer = setInterval(() => {
      if (!document.hidden) {
        this.loadProducts(true);
      }
    }, 8000);

    this.onVisibilityChangeHandler = () => {
      if (document.visibilityState === 'visible') {
        this.loadProducts(true);
      }
    };
    document.addEventListener('visibilitychange', this.onVisibilityChangeHandler);

    this.onFocusHandler = () => {
      this.loadProducts(true);
    };
    window.addEventListener('focus', this.onFocusHandler);

    this.onProductUpdatedHandler = () => {
      this.loadProducts(true);
    };
    window.addEventListener('product-updated', this.onProductUpdatedHandler);
  }

  ngOnDestroy(): void {
    if (this.autoRefreshTimer) {
      clearInterval(this.autoRefreshTimer);
    }
    if (this.onVisibilityChangeHandler) {
      document.removeEventListener('visibilitychange', this.onVisibilityChangeHandler);
    }
    if (this.onFocusHandler) {
      window.removeEventListener('focus', this.onFocusHandler);
    }
    if (this.onProductUpdatedHandler) {
      window.removeEventListener('product-updated', this.onProductUpdatedHandler);
    }
  }

  onSearchInput(value: string): void {
    this.searchQuery.set(value);
    this.showSearchSuggestions.set(value.trim().length > 0);
  }

  selectSuggestion(name: string): void {
    this.searchQuery.set(name);
    this.saveRecentSearch(name);
    this.showSearchSuggestions.set(false);
  }

  applyRecentSearch(term: string): void {
    this.searchQuery.set(term);
  }

  clearRecentSearches(): void {
    this.recentSearches.set([]);
    try {
      localStorage.removeItem('msa_recent_searches');
    } catch {}
  }

  private saveRecentSearch(term: string): void {
    const clean = term.trim();
    if (!clean) return;
    const current = this.recentSearches().filter(t => t.toLowerCase() !== clean.toLowerCase());
    const updated = [clean, ...current].slice(0, 5);
    this.recentSearches.set(updated);
    try {
      localStorage.setItem('msa_recent_searches', JSON.stringify(updated));
    } catch {}
  }

  private getRecentSearches(): string[] {
    try {
      const saved = localStorage.getItem('msa_recent_searches');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  }

  setStockFilter(filter: string): void {
    this.stockFilter.set(filter);
  }

  setPriceTier(min: number | null, max: number | null): void {
    this.minPrice.set(min);
    this.maxPrice.set(max);
  }

  openProductQr(product: ProductWithStock, event?: MouseEvent): void {
    if (event) event.stopPropagation();
    this.qrProduct.set(product);
    this.isQrModalOpen.set(true);
  }

  closeProductQr(): void {
    this.isQrModalOpen.set(false);
    this.qrProduct.set(null);
  }

  openQuickView(product: ProductWithStock, event?: MouseEvent): void {
    if (event) event.stopPropagation();
    this.quickViewProduct.set(product);
    this.isQuickViewOpen.set(true);
  }

  closeQuickView(): void {
    this.isQuickViewOpen.set(false);
    this.quickViewProduct.set(null);
  }

  isNumber(val: number | string): val is number {
    return typeof val === 'number';
  }

  goToPage(page: number): void {
    if (page >= 1 && page <= this.totalPages()) {
      this.currentPage.set(page);
      window.scrollTo({ top: 120, behavior: 'smooth' });
    }
  }

  clearFilters(): void {
    this.searchQuery.set('');
    this.selectedSort.set('recent');
    this.stockFilter.set('all');
    this.minPrice.set(null);
    this.maxPrice.set(null);
    this.currentPage.set(1);
    this.showSearchSuggestions.set(false);
  }

  loadProducts(isSilent: boolean = false): void {
    if (!isSilent && this.products().length === 0) {
      this.isLoading.set(true);
    }
    this.isRefreshing.set(true);
    this.errorMessage.set(null);

    this.productService.getProducts().subscribe({
      next: (data) => {
        const currentProducts = this.products();
        const withStock: ProductWithStock[] = data.map(p => {
          const existing = currentProducts.find(cp => cp.sku === p.sku);
          return {
            ...p,
            inStock: existing ? existing.inStock : undefined,
            stockQuantity: existing ? existing.stockQuantity : undefined,
            checkingStock: existing ? existing.checkingStock : true
          };
        });

        if (currentProducts.length > 0 && data.length > currentProducts.length) {
          const newCount = data.length - currentProducts.length;
          this.toastService.info('Catalog Updated', `${newCount} new product(s) added live.`);
        }

        this.products.set(withStock);
        this.isLoading.set(false);
        this.isRefreshing.set(false);
        const now = new Date();
        this.lastUpdatedText.set(now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }));

        withStock.forEach(p => this.checkStock(p.sku));
      },
      error: (err) => {
        this.isLoading.set(false);
        this.isRefreshing.set(false);

        if (err.status === 401 || err.status === 403) {
          this.errorMessage.set('Your session has expired. Please sign in again.');
        } else if (!isSilent) {
          this.errorMessage.set('Unable to connect to Products Service. Ensure API Gateway is running.');
        }
        console.error(err);
      }
    });
  }

  private checkStock(sku: string): void {
    this.inventoryService.getInventoryDetail(sku).subscribe({
      next: (inv) => {
        const inStock = inv && inv.quantity > 0;
        const stockQuantity = inv ? inv.quantity : 0;
        this.products.update(list =>
          list.map(item =>
            item.sku === sku
              ? { ...item, inStock, stockQuantity, checkingStock: false }
              : item
          )
        );
      },
      error: () => {
        this.inventoryService.isInStock(sku).subscribe({
          next: (inStock) => {
            this.products.update(list =>
              list.map(item =>
                item.sku === sku
                  ? { ...item, inStock, checkingStock: false }
                  : item
              )
            );
          },
          error: () => {
            this.products.update(list =>
              list.map(item =>
                item.sku === sku
                  ? { ...item, checkingStock: false }
                  : item
              )
            );
          }
        });
      }
    });
  }

  onCardMouseMove(event: MouseEvent): void {
    const card = event.currentTarget as HTMLElement;
    const rect = card.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    card.style.setProperty('--mouse-x', `${x}px`);
    card.style.setProperty('--mouse-y', `${y}px`);
  }

  addToCartWithAnimation(product: ProductWithStock, quantity: number = 1, event?: MouseEvent): void {
    this.cartStore.addToCart(product, quantity);
    this.toastService.success('Added to Cart', `${product.name} (x${quantity}) added.`);

    if (event) {
      this.triggerFlyAnimation(event);
    }
  }

  private triggerFlyAnimation(event: MouseEvent): void {
    const btn = (event.currentTarget || event.target) as HTMLElement;
    const rect = btn.getBoundingClientRect();
    const cartBtn = document.querySelector('.cart-trigger-btn') as HTMLElement;

    const startX = rect.left + rect.width / 2;
    const startY = rect.top + rect.height / 2;

    let targetX = window.innerWidth - 80;
    let targetY = 36;

    if (cartBtn) {
      const cartRect = cartBtn.getBoundingClientRect();
      targetX = cartRect.left + cartRect.width / 2;
      targetY = cartRect.top + cartRect.height / 2;
    }

    const dx = targetX - startX;
    const dy = targetY - startY;

    const particle = document.createElement('div');
    particle.className = 'fly-particle';
    particle.style.left = `${startX}px`;
    particle.style.top = `${startY}px`;
    particle.style.setProperty('--dx', `${dx}px`);
    particle.style.setProperty('--dy', `${dy}px`);
    particle.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/></svg>`;

    document.body.appendChild(particle);

    setTimeout(() => {
      particle.remove();
    }, 650);
  }
}
