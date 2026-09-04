import { Component, ChangeDetectionStrategy, input, output, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ProductResponse } from '../../../core/models/product.model';
import { CurrencyService } from '../../../core/services/currency.service';
import { KeycloakService } from '../../../core/auth/keycloak.service';
import { TranslatePipe } from '../../../core/pipes/translate.pipe';
import { getProductImageUrl } from '../../../core/utils/product-image.helper';

interface ProductWithStock extends ProductResponse {
  inStock?: boolean;
  stockQuantity?: number;
  checkingStock?: boolean;
}

@Component({
  selector: 'app-quick-view-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './quick-view-modal.component.html',
  styleUrls: ['./quick-view-modal.component.css']
})
export class ProductQuickViewModalComponent {
  readonly isOpen = input<boolean>(false);
  readonly product = input<ProductWithStock | null>(null);
  readonly closeEvent = output<void>();
  readonly addEvent = output<{ product: ProductWithStock; quantity: number; event: MouseEvent }>();

  readonly quantity = signal<number>(1);
  readonly currencyService = inject(CurrencyService);
  readonly keycloakService = inject(KeycloakService);
  readonly getProductImageUrl = getProductImageUrl;

  getProductCategory(prod?: ProductWithStock | null): string {
    if (!prod) return 'Hardware';
    if (prod.category) return prod.category;
    const q = `${prod.sku} ${prod.name}`.toLowerCase();
    if (q.includes('laptop') || q.includes('macbook') || q.includes('pc')) return 'Computers';
    if (q.includes('keyboard') || q.includes('teclado')) return 'Peripherals';
    if (q.includes('mouse') || q.includes('raton')) return 'Peripherals';
    if (q.includes('monitor') || q.includes('display') || q.includes('screen')) return 'Displays';
    if (q.includes('headphone') || q.includes('audifono') || q.includes('audio')) return 'Audio';
    return 'Electronics';
  }

  onImageError(event: Event): void {
    const target = event.target as HTMLImageElement;
    const prod = this.product();
    if (target && prod) {
      target.src = getProductImageUrl({ sku: prod.sku, name: prod.name });
    }
  }

  close(): void {
    this.quantity.set(1);
    this.closeEvent.emit();
  }

  onLogin(): void {
    this.close();
    this.keycloakService.login();
  }

  incQty(): void {
    this.quantity.update(q => q + 1);
  }

  decQty(): void {
    this.quantity.update(q => Math.max(1, q - 1));
  }

  onAddToCart(event: MouseEvent): void {
    const currentProd = this.product();
    if (!currentProd) return;
    this.addEvent.emit({
      product: currentProd,
      quantity: this.quantity(),
      event
    });
    this.close();
  }
}
