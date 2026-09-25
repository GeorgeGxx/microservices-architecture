import { Component, ChangeDetectionStrategy, inject, signal, computed, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { KeycloakService } from '../../../core/auth/keycloak.service';
import { CartStore } from '../../../core/services/cart.store';
import { NotificationCenterService } from '../../../core/services/notification-center.service';
import { ScannerModalService } from '../../../core/services/scanner-modal.service';
import { CurrencyService } from '../../../core/services/currency.service';
import { CommandPaletteService } from '../../../core/services/command-palette.service';
import { WishlistService } from '../../../core/services/wishlist.service';
import { SystemStatusService } from '../../../core/services/system-status.service';

@Component({
  selector: 'app-navbar',
  standalone: true,
  imports: [CommonModule, RouterModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './navbar.component.html',
  styleUrl: './navbar.component.css'
})
export class NavbarComponent implements OnInit, OnDestroy {
  readonly keycloakService = inject(KeycloakService);
  readonly cartStore = inject(CartStore);
  readonly notifService = inject(NotificationCenterService);
  readonly scannerModal = inject(ScannerModalService);
  readonly currencyService = inject(CurrencyService);
  readonly palette = inject(CommandPaletteService);
  readonly wishlist = inject(WishlistService);
  readonly statusService = inject(SystemStatusService);
  private readonly router = inject(Router);

  readonly showNotifications = signal<boolean>(false);
  private healthCheckTimer?: ReturnType<typeof setInterval>;

  readonly healthState = computed<'green' | 'orange' | 'red'>(() => {
    const list = this.statusService.services();
    const downCount = list.filter(s => s.status === 'DOWN').length;
    if (downCount === 0) return 'green';
    if (downCount <= 2) return 'orange';
    return 'red';
  });

  readonly healthTooltip = computed<string>(() => {
    const list = this.statusService.services();
    const total = list.length;
    const downServices = list.filter(s => s.status === 'DOWN');
    const state = this.healthState();

    if (state === 'green') {
      return `Admin Panel • All ${total} microservices operational`;
    } else if (state === 'orange') {
      const names = downServices.map(s => s.name).join(', ');
      return `Admin Panel • Degraded (${names} offline)`;
    } else {
      return `Admin Panel • Critical (${downServices.length}/${total} microservices offline)`;
    }
  });

  ngOnInit(): void {
    this.statusService.checkAllServices();
    this.healthCheckTimer = setInterval(() => {
      this.statusService.checkAllServices();
    }, 30000);
  }

  ngOnDestroy(): void {
    if (this.healthCheckTimer) {
      clearInterval(this.healthCheckTimer);
    }
  }

  toggleNotifications(): void {
    this.showNotifications.update(v => !v);
  }

  openScanner(): void {
    this.scannerModal.open();
  }
}
