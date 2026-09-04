import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AgnosticQrScannerService, ScanResult } from '../../../core/services/agnostic-qr-scanner.service';
import { ProductService } from '../../../core/services/product.service';
import { CartStore } from '../../../core/services/cart.store';
import { ToastService } from '../../../core/services/toast.service';
import { TranslationService } from '../../../core/services/translation.service';
import { TranslatePipe } from '../../../core/pipes/translate.pipe';
import { ProductResponse } from '../../../core/models/product.model';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { ScannerModalService } from '../../../core/services/scanner-modal.service';

@Component({
  selector: 'app-qr-scanner-modal',
  standalone: true,
  imports: [CommonModule, FormsModule, TranslatePipe],
  templateUrl: './qr-scanner-modal.component.html',
  styleUrls: ['./qr-scanner-modal.component.css']
})
export class QrScannerModalComponent implements OnInit, OnDestroy {
  readonly modalService = inject(ScannerModalService);
  readonly scannerService = inject(AgnosticQrScannerService);
  private readonly productService = inject(ProductService);
  private readonly cartStore = inject(CartStore);
  private readonly toastService = inject(ToastService);
  readonly translationService = inject(TranslationService);
  private readonly router = inject(Router);

  @ViewChild('videoPreview') videoPreview?: ElementRef<HTMLVideoElement>;

  readonly activeTab = signal<'CAMERA' | 'FILE' | 'HARDWARE'>('CAMERA');
  readonly manualInput = signal<string>('');
  readonly isProcessing = signal<boolean>(false);
  readonly lastScan = signal<ScanResult | null>(null);
  readonly matchedProduct = signal<ProductResponse | null>(null);
  readonly isOrderCode = signal<boolean>(false);

  private scanSub?: Subscription;
  private cameraInterval?: any;
  private currentFacing: 'environment' | 'user' = 'environment';

  ngOnInit(): void {
    this.scanSub = this.scannerService.scannedCode$.subscribe((result) => {
      this.handleScanResult(result);
    });
  }

  ngOnDestroy(): void {
    this.scanSub?.unsubscribe();
    this.closeModal();
  }

  isOpen(): boolean {
    return this.modalService.isOpen();
  }

  openModal(): void {
    this.modalService.open();
    this.lastScan.set(null);
    this.matchedProduct.set(null);
    this.isOrderCode.set(false);
    this.activeTab.set('CAMERA');

    setTimeout(() => {
      this.startCameraStream();
    }, 150);
  }

  closeModal(): void {
    this.stopCameraStream();
    this.modalService.close();
  }

  setTab(tab: 'CAMERA' | 'FILE' | 'HARDWARE'): void {
    this.activeTab.set(tab);
    if (tab === 'CAMERA') {
      this.startCameraStream();
    } else {
      this.stopCameraStream();
    }
  }

  private async startCameraStream(): Promise<void> {
    if (!this.videoPreview?.nativeElement) return;
    const ok = await this.scannerService.startCamera(this.videoPreview.nativeElement, this.currentFacing);
    if (ok) {
      this.cameraInterval = setInterval(async () => {
        if (this.videoPreview?.nativeElement && this.isOpen() && this.activeTab() === 'CAMERA') {
          await this.scannerService.scanVideoFrame(this.videoPreview.nativeElement);
        }
      }, 250);
    }
  }

  private stopCameraStream(): void {
    if (this.cameraInterval) {
      clearInterval(this.cameraInterval);
      this.cameraInterval = null;
    }
    this.scannerService.stopCamera();
  }

  toggleCameraLens(): void {
    this.currentFacing = this.currentFacing === 'environment' ? 'user' : 'environment';
    this.startCameraStream();
  }

  toggleFlash(): void {
    this.scannerService.toggleTorch();
  }

  async onFileSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    if (input.files && input.files.length > 0) {
      const file = input.files[0];
      this.isProcessing.set(true);
      await this.scannerService.decodeImageFile(file);
      this.isProcessing.set(false);
    }
  }

  onManualSubmit(): void {
    const code = this.manualInput().trim();
    if (code) {
      this.scannerService.emitScanResult(code, 'MANUAL');
      this.manualInput.set('');
    }
  }

  private async handleScanResult(result: ScanResult): Promise<void> {
    this.lastScan.set(result);
    this.isProcessing.set(true);

    const codeUpper = result.code.toUpperCase();

    // Check if code corresponds to Order ID
    if (codeUpper.startsWith('ORD-')) {
      this.isOrderCode.set(true);
      this.matchedProduct.set(null);
      this.toastService.success('Order Code Decoded', `Receipt #${result.code} verified.`);
      this.isProcessing.set(false);
      return;
    }

    this.isOrderCode.set(false);

    // Look up in Product Catalog by SKU or ID
    try {
      const products = await new Promise<ProductResponse[]>((resolve) => {
        this.productService.getProducts().subscribe({
          next: (res) => resolve(res),
          error: () => resolve([])
        });
      });

      const found = products.find(p => 
        p.sku?.toUpperCase() === codeUpper || 
        p.id?.toString() === codeUpper ||
        p.name?.toUpperCase().includes(codeUpper)
      );

      if (found) {
        this.matchedProduct.set(found);
        this.toastService.success('Product Found', `SKU matched: ${found.name}`);
      } else {
        this.matchedProduct.set(null);
        this.toastService.info('QR Scanned', `Code: ${result.code} (No matching product SKU)`);
      }
    } catch (e) {
      this.matchedProduct.set(null);
    } finally {
      this.isProcessing.set(false);
    }
  }

  addScannedProductToCart(): void {
    const product = this.matchedProduct();
    if (product) {
      this.cartStore.addToCart(product, 1);
      this.toastService.success('Added to Cart', `${product.name} added to cart!`);
      this.closeModal();
    }
  }

  goToOrders(): void {
    this.closeModal();
    this.router.navigate(['/orders']);
  }
}
