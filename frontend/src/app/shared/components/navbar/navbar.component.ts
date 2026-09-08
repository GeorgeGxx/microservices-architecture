import { Component, ChangeDetectionStrategy, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { KeycloakService } from '../../../core/auth/keycloak.service';
import { CartStore } from '../../../core/services/cart.store';
import { NotificationCenterService } from '../../../core/services/notification-center.service';
import { ThemeService, AppTheme } from '../../../core/services/theme.service';
import { ScannerModalService } from '../../../core/services/scanner-modal.service';
import { CurrencyService } from '../../../core/services/currency.service';

@Component({
  selector: 'app-navbar',
  standalone: true,
  imports: [CommonModule, RouterModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './navbar.component.html',
  styleUrl: './navbar.component.css'
})
export class NavbarComponent {
  readonly keycloakService = inject(KeycloakService);
  readonly cartStore = inject(CartStore);
  readonly notifService = inject(NotificationCenterService);
  readonly themeService = inject(ThemeService);
  readonly scannerModal = inject(ScannerModalService);
  readonly currencyService = inject(CurrencyService);

  readonly showNotifications = signal<boolean>(false);
  readonly showThemeMenu = signal<boolean>(false);

  toggleNotifications(): void {
    this.showNotifications.update(v => !v);
  }

  toggleThemeMenu(): void {
    this.showThemeMenu.update(v => !v);
  }

  setTheme(theme: AppTheme): void {
    this.themeService.setTheme(theme);
    this.showThemeMenu.set(false);
  }

  openScanner(): void {
    this.scannerModal.open();
  }
}
