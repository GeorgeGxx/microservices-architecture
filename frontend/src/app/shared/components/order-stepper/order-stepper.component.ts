import { Component, ChangeDetectionStrategy, OnInit, OnDestroy, computed, signal, input } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-order-stepper',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  templateUrl: './order-stepper.component.html',
  styleUrls: ['./order-stepper.component.css']
})
export class OrderStepperComponent implements OnInit, OnDestroy {
  readonly status = input<string | undefined>();
  readonly trackingNumber = input<string | undefined>();
  readonly carrier = input<string | undefined>();
  readonly deliveryMethod = input<string | undefined>();
  readonly shippingAddress = input<string | undefined>();

  readonly simulatedStatus = signal<string | null>(null);
  readonly isSimulating = signal<boolean>(false);
  readonly simSeconds = signal<number>(0);
  private simTimer?: ReturnType<typeof setInterval>;

  ngOnInit(): void {}

  ngOnDestroy(): void {
    if (this.simTimer) {
      clearInterval(this.simTimer);
    }
  }

  readonly effectiveStatus = computed(() => {
    return this.simulatedStatus() || this.status() || 'PLACED';
  });

  readonly isCancelled = computed(() => this.effectiveStatus() === 'CANCELLED');

  readonly activeStageLabel = computed(() => {
    const s = this.effectiveStatus();
    switch (s) {
      case 'CANCELLED': return 'Cancelled';
      case 'DELIVERED': return 'Delivered to Destination';
      case 'SHIPPED': return 'In Transit with Courier';
      default: return 'Order Confirmed - Preparing';
    }
  });

  readonly steps = computed(() => {
    const s = this.effectiveStatus();
    return [
      { id: 1, title: 'Placed', desc: 'Payment Confirmed', completed: true, active: false },
      { id: 2, title: 'Preparing', desc: 'Fulfillment Hub', completed: s === 'SHIPPED' || s === 'DELIVERED', active: s === 'PLACED' },
      { id: 3, title: 'In Transit', desc: this.carrier() || 'DHL Express', completed: s === 'DELIVERED', active: s === 'SHIPPED' },
      { id: 4, title: 'Out for Delivery', desc: 'Local Depot', completed: s === 'DELIVERED', active: false },
      { id: 5, title: 'Delivered', desc: 'Handed Over', completed: s === 'DELIVERED', active: false }
    ];
  });

  toggleSimulation(): void {
    if (this.isSimulating()) {
      this.stopSimulation();
      return;
    }

    this.isSimulating.set(true);
    this.simSeconds.set(0);

    this.simTimer = setInterval(() => {
      this.simSeconds.update(s => s + 1);
      const sec = this.simSeconds();

      if (sec === 8) {
        this.simulatedStatus.set('SHIPPED');
      } else if (sec === 18) {
        this.simulatedStatus.set('DELIVERED');
        this.stopSimulation();
      }
    }, 1000);
  }

  private stopSimulation(): void {
    this.isSimulating.set(false);
    if (this.simTimer) {
      clearInterval(this.simTimer);
    }
  }
}
