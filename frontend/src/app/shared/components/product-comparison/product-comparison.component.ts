import { Component, ChangeDetectionStrategy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ComparisonService } from '../../../core/services/comparison.service';
import { CartStore } from '../../../core/services/cart.store';
import { CurrencyService } from '../../../core/services/currency.service';
import { ToastService } from '../../../core/services/toast.service';
import { getProductImageUrl } from '../../../core/utils/product-image.helper';
import { ProductResponse } from '../../../core/models/product.model';

@Component({
  selector: 'app-product-comparison',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './product-comparison.component.html',
  styleUrl: './product-comparison.component.css'
})
export class ProductComparisonComponent {
  readonly comparison = inject(ComparisonService);
  private readonly cartStore = inject(CartStore);
  readonly currencyService = inject(CurrencyService);
  private readonly toast = inject(ToastService);
  readonly getProductImageUrl = getProductImageUrl;

  addToCart(product: ProductResponse): void {
    this.cartStore.addToCart(product, 1);
    this.toast.success('Added to Cart', `${product.name} added.`);
  }
}
