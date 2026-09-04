import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { NavbarComponent } from './shared/components/navbar/navbar.component';
import { ToastComponent } from './shared/components/toast/toast.component';
import { CartDrawerComponent } from './shared/components/cart-drawer/cart-drawer.component';

import { QrScannerModalComponent } from './shared/components/qr-scanner-modal/qr-scanner-modal.component';

import { TranslatePipe } from './core/pipes/translate.pipe';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, NavbarComponent, ToastComponent, CartDrawerComponent, QrScannerModalComponent, TranslatePipe],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})
export class AppComponent {
  title = 'MicroStore - Microservices Frontend';
}
