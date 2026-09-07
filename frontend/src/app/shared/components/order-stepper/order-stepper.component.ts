import { Component, ChangeDetectionStrategy, OnInit, OnDestroy, computed, signal, input, output, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { OrderService } from '../../../core/services/order.service';
import { ToastService } from '../../../core/services/toast.service';
import { NotificationCenterService } from '../../../core/services/notification-center.service';

export interface DeliveryStep {
  id: number;
  title: string;
  desc: string;
  completed: boolean;
  active: boolean;
}

@Component({
  selector: 'app-order-stepper',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  templateUrl: './order-stepper.component.html',
  styleUrls: ['./order-stepper.component.css']
})
export class OrderStepperComponent implements OnInit, OnDestroy {
  readonly orderId = input<number | undefined>();
  readonly orderNumber = input<string | undefined>();
  readonly status = input<string | undefined>();
  readonly trackingNumber = input<string | undefined>();
  readonly carrier = input<string | undefined>();
  readonly deliveryMethod = input<string | undefined>();
  readonly shippingAddress = input<string | undefined>();
  readonly city = input<string | undefined>();
  readonly statusChange = output<{ orderId?: number; status: 'PLACED' | 'CANCELLED' | 'SHIPPED' | 'DELIVERED' }>();
  readonly stageChange = output<{ orderId?: number; stage: number; stageName: string }>();

  private readonly orderService = inject(OrderService);
  private readonly toastService = inject(ToastService);
  private readonly notifService = inject(NotificationCenterService);

  readonly simulatedStatus = signal<string | null>(null);
  readonly isLiveFlowRunning = signal<boolean>(false);
  readonly liveStage = signal<number>(1);
  private timers: ReturnType<typeof setTimeout>[] = [];

  ngOnInit(): void {}

  ngOnDestroy(): void {
    this.clearAllTimers();
  }

  private clearAllTimers(): void {
    this.timers.forEach(t => clearTimeout(t));
    this.timers = [];
  }

  readonly effectiveStatus = computed(() => {
    return this.simulatedStatus() || this.status() || 'PLACED';
  });

  readonly isCancelled = computed(() => this.effectiveStatus() === 'CANCELLED');

  readonly effectiveStage = computed(() => {
    if (this.isLiveFlowRunning()) {
      return this.liveStage();
    }
    const s = this.effectiveStatus();
    switch (s) {
      case 'CANCELLED': return 0;
      case 'DELIVERED': return 5;
      case 'SHIPPED': return 3;
      default: return 1; // Stage 1: Placed
    }
  });

  readonly courierPositionPercent = computed(() => {
    const stage = this.effectiveStage();
    switch (stage) {
      case 1: return 0;
      case 2: return 25;
      case 3: return 50;
      case 4: return 75;
      case 5: return 100;
      default: return 0;
    }
  });

  readonly liveStageName = computed(() => {
    const stage = this.effectiveStage();
    switch (stage) {
      case 1: return 'Placed';
      case 2: return 'Preparing';
      case 3: return 'In Transit';
      case 4: return 'Out for Delivery';
      case 5: return 'Delivered';
      default: return 'Processing';
    }
  });

  readonly activeStageLabel = computed(() => {
    const s = this.effectiveStatus();
    if (this.isLiveFlowRunning()) {
      return `Live: ${this.liveStageName()}`;
    }
    switch (s) {
      case 'CANCELLED': return 'Cancelled';
      case 'DELIVERED': return 'Delivered to Destination';
      case 'SHIPPED': return 'In Transit with Carrier';
      default: return 'Order Placed - Confirmed';
    }
  });

  readonly steps = computed<DeliveryStep[]>(() => {
    const stage = this.effectiveStage();
    const carrierName = this.carrier() || 'DHL Express';
    const destination = this.city() ? `Courier in ${this.city()}` : 'Local Courier';

    return [
      {
        id: 1,
        title: 'Placed',
        desc: 'Payment Confirmed',
        completed: stage >= 1,
        active: stage === 1
      },
      {
        id: 2,
        title: 'Preparing',
        desc: 'Fulfillment Hub',
        completed: stage > 2 || stage === 5,
        active: stage === 2
      },
      {
        id: 3,
        title: 'In Transit',
        desc: carrierName,
        completed: stage > 3 || stage === 5,
        active: stage === 3
      },
      {
        id: 4,
        title: 'Out for Delivery',
        desc: destination,
        completed: stage > 4 || stage === 5,
        active: stage === 4
      },
      {
        id: 5,
        title: 'Delivered',
        desc: 'Handed Over',
        completed: stage === 5,
        active: stage === 5
      }
    ];
  });

  startLiveDeliveryFlow(): void {
    if (this.isLiveFlowRunning() || this.isCancelled()) return;

    this.clearAllTimers();
    this.isLiveFlowRunning.set(true);

    const num = this.orderNumber() ? this.orderNumber()!.substring(0, 8).toUpperCase() : 'PENDING';
    const carrierName = this.carrier() || 'DHL Express';
    const tracking = this.trackingNumber() || 'DHL-EXP-LIVE';
    const dest = this.city() || 'your address';
    const orderIdVal = this.orderId();

    // Stage 1: Placed (Immediate)
    this.liveStage.set(1);
    this.stageChange.emit({ orderId: orderIdVal, stage: 1, stageName: 'Placed' });
    this.toastService.info('Stage 1/5: Order Placed', `Order #${num} payment verified and logged in database.`);
    this.notifService.addNotification({
      title: `Order #${num} Confirmed`,
      message: `Payment authorized. Inventory reserved in Postgres cluster.`,
      type: 'info'
    });

    // Stage 2: Preparing (after 2.2s) - Warehouse Hub
    const t2 = setTimeout(() => {
      this.liveStage.set(2);
      this.stageChange.emit({ orderId: orderIdVal, stage: 2, stageName: 'Preparing' });
      this.toastService.info('Stage 2/5: Warehouse Hub (Preparing)', `Order #${num} is being picked, packed & barcoded. Cancellation locked.`);
      this.notifService.addNotification({
        title: `Order #${num} Packaging`,
        message: `Fulfillment Center completed quality inspection and carton seal. Cancellation locked.`,
        type: 'info'
      });
    }, 2200);
    this.timers.push(t2);

    // Stage 3: In Transit (after 4.8s) - Carrier Handover
    const t3 = setTimeout(() => {
      this.liveStage.set(3);
      this.stageChange.emit({ orderId: orderIdVal, stage: 3, stageName: 'In Transit' });
      if (orderIdVal) {
        this.orderService.shipOrder(orderIdVal).subscribe({
          next: () => this.statusChange.emit({ orderId: orderIdVal, status: 'SHIPPED' }),
          error: () => {}
        });
      }
      this.toastService.success('Stage 3/5: Dispatched & In Transit', `Departed fulfillment hub via ${carrierName} (${tracking}).`);
      this.notifService.addNotification({
        title: `Order #${num} Dispatched`,
        message: `Package handed over to ${carrierName}. Tracking code: ${tracking}.`,
        type: 'success'
      });
    }, 4800);
    this.timers.push(t3);

    // Stage 4: Out for Delivery (after 7.6s) - Local Courier
    const t4 = setTimeout(() => {
      this.liveStage.set(4);
      this.stageChange.emit({ orderId: orderIdVal, stage: 4, stageName: 'Out for Delivery' });
      this.toastService.info('Stage 4/5: Out for Delivery', `Courier vehicle is on route in ${dest}. Arriving shortly!`);
      this.notifService.addNotification({
        title: `Courier Out for Delivery`,
        message: `Delivery van is in ${dest}. Expected delivery in minutes.`,
        type: 'info'
      });
    }, 7600);
    this.timers.push(t4);

    // Stage 5: Delivered (after 10.4s) - Final Delivery Handover
    const t5 = setTimeout(() => {
      this.liveStage.set(5);
      this.simulatedStatus.set('DELIVERED');
      this.isLiveFlowRunning.set(false);
      this.stageChange.emit({ orderId: orderIdVal, stage: 5, stageName: 'Delivered' });

      if (orderIdVal) {
        this.orderService.deliverOrder(orderIdVal).subscribe({
          next: () => this.statusChange.emit({ orderId: orderIdVal, status: 'DELIVERED' }),
          error: () => {}
        });
      }

      this.statusChange.emit({ orderId: orderIdVal, status: 'DELIVERED' });
      this.toastService.success('Stage 5/5: Package Delivered!', `Order #${num} successfully handed over at ${dest}. Enjoy your purchase!`);
      this.notifService.addNotification({
        title: `Order #${num} Delivered!`,
        message: `Package signed and handed over. Thank you for shopping with MicroStore!`,
        type: 'success'
      });
    }, 10400);
    this.timers.push(t5);
  }
}
