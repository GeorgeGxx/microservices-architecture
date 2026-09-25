import { Component, ChangeDetectionStrategy, HostListener, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CommandPaletteService } from '../../../core/services/command-palette.service';
import { ProductService } from '../../../core/services/product.service';
import { CartStore } from '../../../core/services/cart.store';
import { ScannerModalService } from '../../../core/services/scanner-modal.service';
import { CurrencyService, CurrencyCode } from '../../../core/services/currency.service';
import { KeycloakService } from '../../../core/auth/keycloak.service';
import { ToastService } from '../../../core/services/toast.service';
import { ComparisonService } from '../../../core/services/comparison.service';
import { ProductResponse } from '../../../core/models/product.model';

interface PaletteCommand {
  id: string;
  title: string;
  subtitle?: string;
  category: 'Navigation' | 'Actions' | 'Products' | 'Currency';
  icon: string;
  shortcut?: string;
  action: () => void;
}

@Component({
  selector: 'app-command-palette',
  standalone: true,
  imports: [CommonModule, FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './command-palette.component.html',
  styleUrl: './command-palette.component.css'
})
export class CommandPaletteComponent {
  readonly palette = inject(CommandPaletteService);
  private readonly router = inject(Router);
  private readonly productService = inject(ProductService);
  private readonly cartStore = inject(CartStore);
  private readonly scannerModal = inject(ScannerModalService);
  private readonly currencyService = inject(CurrencyService);
  readonly comparison = inject(ComparisonService);
  readonly keycloakService = inject(KeycloakService);
  private readonly toast = inject(ToastService);

  readonly searchQuery = signal<string>('');
  readonly selectedIndex = signal<number>(0);

  @HostListener('window:keydown', ['$event'])
  handleGlobalShortcut(event: KeyboardEvent): void {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      this.palette.toggle();
      if (this.palette.isOpen()) {
        this.searchQuery.set('');
        this.selectedIndex.set(0);
      }
    } else if (event.key === 'Escape' && this.palette.isOpen()) {
      this.palette.close();
    }
  }

  readonly allStaticCommands: PaletteCommand[] = [
    {
      id: 'nav-catalog',
      title: 'Products Catalog',
      subtitle: 'Browse microservices store items and live inventory',
      category: 'Navigation',
      icon: 'grid',
      shortcut: 'G P',
      action: () => this.navigate('/')
    },
    {
      id: 'nav-orders',
      title: 'Orders & Receipts',
      subtitle: 'Track order status, delivery progress and cryptographic receipts',
      category: 'Navigation',
      icon: 'box',
      shortcut: 'G O',
      action: () => this.navigate('/orders')
    },
    {
      id: 'nav-checkout',
      title: 'Checkout & Payment',
      subtitle: 'Review cart items and dispatch distributed checkout',
      category: 'Navigation',
      icon: 'credit-card',
      shortcut: 'G C',
      action: () => this.navigate('/checkout')
    },
    {
      id: 'nav-admin',
      title: 'Admin Control Center',
      subtitle: 'Manage products, stock alerts and platform metrics',
      category: 'Navigation',
      icon: 'shield',
      shortcut: 'G A',
      action: () => this.navigate('/admin')
    },
    {
      id: 'act-compare',
      title: 'Product Comparison',
      subtitle: 'Open side-by-side technical specification comparison modal',
      category: 'Actions',
      icon: 'box',
      shortcut: 'Alt C',
      action: () => {
        this.palette.close();
        this.comparison.openDrawer();
      }
    },
    {
      id: 'act-scanner',
      title: 'Open QR & Barcode Scanner',
      subtitle: 'Universal camera scanner for POS and cashier terminal',
      category: 'Actions',
      icon: 'qr',
      shortcut: 'Alt S',
      action: () => {
        this.palette.close();
        this.scannerModal.open();
      }
    },
    {
      id: 'act-clear-cart',
      title: 'Clear Shopping Cart',
      subtitle: 'Empty current items from reactive cart store',
      category: 'Actions',
      icon: 'trash',
      action: () => {
        this.cartStore.clearCart();
        this.palette.close();
        this.toast.info('Shopping cart cleared.');
      }
    },
    {
      id: 'curr-usd',
      title: 'Active Currency: USD ($)',
      subtitle: 'United States Dollar (Reference Base)',
      category: 'Currency',
      icon: 'dollar',
      action: () => this.selectCurrency('USD')
    }
  ];

  readonly filteredCommands = computed(() => {
    const q = this.searchQuery().trim().toLowerCase();
    const isAdmin = this.keycloakService.isAdmin();

    // Hide admin-only telemetry & management actions from basic users
    const allowed = this.allStaticCommands.filter(c => {
      if (!isAdmin && (c.id === 'nav-admin' || c.id === 'act-scanner')) {
        return false;
      }
      return true;
    });

    const staticCmds = q
      ? allowed.filter(
          c => c.title.toLowerCase().includes(q) || (c.subtitle && c.subtitle.toLowerCase().includes(q))
        )
      : allowed;

    // Dynamically include matching products from catalog
    let productCmds: PaletteCommand[] = [];
    if (q) {
      const allProducts = Array.from(this.productService.productsMap().values());
      const matched = allProducts.filter(
        (p: ProductResponse) => (p.name && p.name.toLowerCase().includes(q)) || (p.sku && p.sku.toLowerCase().includes(q))
      ).slice(0, 5);

      productCmds = matched.map((p: ProductResponse) => ({
        id: `prod-${p.id || p.sku}`,
        title: p.name,
        subtitle: `SKU: ${p.sku} | $${(p.price || 0).toFixed(2)}`,
        category: 'Products' as const,
        icon: 'package',
        action: () => {
          this.palette.close();
          this.cartStore.addToCart(p, 1);
          this.toast.success('Added to Cart', `Added "${p.name}" to cart.`);
        }
      }));
    }

    return [...staticCmds, ...productCmds];
  });

  onKeyDown(event: KeyboardEvent): void {
    const list = this.filteredCommands();
    if (list.length === 0) return;

    if (event.key === 'ArrowDown') {
      event.preventDefault();
      this.selectedIndex.update(i => (i + 1) % list.length);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      this.selectedIndex.update(i => (i - 1 + list.length) % list.length);
    } else if (event.key === 'Enter') {
      event.preventDefault();
      const selected = list[this.selectedIndex()];
      if (selected) {
        selected.action();
      }
    }
  }

  execute(cmd: PaletteCommand): void {
    cmd.action();
  }

  private navigate(path: string): void {
    this.palette.close();
    this.router.navigate([path]);
  }

  private selectCurrency(code: CurrencyCode): void {
    this.currencyService.setCurrency(code);
    this.palette.close();
    this.toast.success(`Active currency changed to ${code}`);
  }
}
