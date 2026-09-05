import { Component, ChangeDetectionStrategy, input, output, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';
import { OrderResponse } from '../../../core/models/order.model';
import { QrGeneratorService } from '../../../core/services/qr-generator.service';
import { ProductService } from '../../../core/services/product.service';

@Component({
  selector: 'app-receipt-modal',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './receipt-modal.component.html',
  styleUrls: ['./receipt-modal.component.css']
})
export class ReceiptModalComponent {
  readonly isOpen = input<boolean>(false);
  readonly order = input<OrderResponse | null>(null);
  readonly closeEvent = output<void>();

  readonly today = new Date();
  private readonly qrGenerator = inject(QrGeneratorService);
  private readonly sanitizer = inject(DomSanitizer);
  readonly productService = inject(ProductService);

  qrSvg(): SafeHtml {
    const currentOrder = this.order();
    if (!currentOrder?.orderNumber) return '';
    const svg = this.qrGenerator.generateQrSvg(`ORD-${currentOrder.orderNumber}`, 140, '#0f172a', '#f8fafc');
    return this.sanitizer.bypassSecurityTrustHtml(svg);
  }

  subtotal(): number {
    const currentOrder = this.order();
    if (!currentOrder || !currentOrder.orderItems) return 0;
    return currentOrder.orderItems.reduce((acc, item) => acc + (item.price * item.quantity), 0);
  }

  getItemImageUrl(sku: string): string {
    return this.productService.getProductImage(sku);
  }

  getItemName(sku: string): string {
    return this.productService.getProductName(sku);
  }

  close(): void {
    this.closeEvent.emit();
  }

  printReceipt(): void {
    window.print();
  }
}
