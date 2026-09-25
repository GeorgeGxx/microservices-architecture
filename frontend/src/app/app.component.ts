import { Component, inject } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NavbarComponent } from './shared/components/navbar/navbar.component';
import { ToastComponent } from './shared/components/toast/toast.component';
import { CartDrawerComponent } from './shared/components/cart-drawer/cart-drawer.component';
import { QrScannerModalComponent } from './shared/components/qr-scanner-modal/qr-scanner-modal.component';
import { CommandPaletteComponent } from './shared/components/command-palette/command-palette.component';
import { ProductComparisonComponent } from './shared/components/product-comparison/product-comparison.component';
import { KeycloakService } from './core/auth/keycloak.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [
    RouterOutlet,
    NavbarComponent,
    ToastComponent,
    CartDrawerComponent,
    QrScannerModalComponent,
    CommandPaletteComponent,
    ProductComparisonComponent
  ],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})
export class AppComponent {
  title = 'MicroStore - Microservices Frontend';
  readonly keycloakService = inject(KeycloakService);
}
