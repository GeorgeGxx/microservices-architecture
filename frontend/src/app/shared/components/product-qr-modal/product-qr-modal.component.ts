import { Component, ChangeDetectionStrategy, input, output, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DomSanitizer, SafeHtml } from '@angular/platform-browser';
import { ProductResponse } from '../../../core/models/product.model';
import { QrGeneratorService } from '../../../core/services/qr-generator.service';

@Component({
  selector: 'app-product-qr-modal',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './product-qr-modal.component.html',
  styleUrls: ['./product-qr-modal.component.css']
})
export class ProductQrModalComponent {
  readonly isOpen = input<boolean>(false);
  readonly product = input<ProductResponse | null>(null);
  readonly closeEvent = output<void>();

  private readonly qrGenerator = inject(QrGeneratorService);
  private readonly sanitizer = inject(DomSanitizer);

  qrSvg(): SafeHtml {
    const currentProd = this.product();
    if (!currentProd?.sku) return '';
    const svg = this.qrGenerator.generateQrSvg(currentProd.sku, 170, '#0f172a', '#ffffff');
    return this.sanitizer.bypassSecurityTrustHtml(svg);
  }

  close(): void {
    this.closeEvent.emit();
  }

  printLabel(): void {
    window.print();
  }
}
