import { Component, ChangeDetectionStrategy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { CartStore } from '../../../core/services/cart.store';
import { KeycloakService } from '../../../core/auth/keycloak.service';
import { ScannerModalService } from '../../../core/services/scanner-modal.service';
import { CurrencyService } from '../../../core/services/currency.service';
import { TranslatePipe } from '../../../core/pipes/translate.pipe';
import { getProductImageUrl } from '../../../core/utils/product-image.helper';

@Component({
  selector: 'app-cart-drawer',
  standalone: true,
  imports: [CommonModule, TranslatePipe],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './cart-drawer.component.html',
  styleUrl: './cart-drawer.component.css'
})
export class CartDrawerComponent {
  readonly cartStore = inject(CartStore);
  readonly scannerModal = inject(ScannerModalService);
  readonly currencyService = inject(CurrencyService);
  readonly keycloakService = inject(KeycloakService);
  readonly getProductImageUrl = getProductImageUrl;
  private readonly router = inject(Router);

  goToCheckout(): void {
    this.cartStore.toggleCart(false);
    this.router.navigate(['/checkout']);
  }

  openScanner(): void {
    this.scannerModal.open();
  }
}
