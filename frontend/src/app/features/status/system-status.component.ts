import { Component, OnInit, computed, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SystemStatusService } from '../../core/services/system-status.service';

@Component({
  selector: 'app-system-status',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './system-status.component.html',
  styleUrl: './system-status.component.css'
})
export class SystemStatusComponent implements OnInit {
  readonly statusService = inject(SystemStatusService);

  readonly onlineCount = computed(() =>
    this.statusService.services().filter(s => s.status === 'UP').length
  );

  readonly allUp = computed(() =>
    this.onlineCount() === this.statusService.services().length
  );

  readonly uptimePercent = computed(() => {
    const total = this.statusService.services().length;
    if (total === 0) return 100;
    return Math.round((this.onlineCount() / total) * 100);
  });

  readonly avgLatency = computed(() => {
    const valid = this.statusService.services().filter(s => s.latencyMs !== undefined);
    if (valid.length === 0) return 0;
    const total = valid.reduce((acc, curr) => acc + (curr.latencyMs || 0), 0);
    return Math.round(total / valid.length);
  });

  ngOnInit(): void {
    const firstService = this.statusService.services()[0];
    if (!firstService?.lastChecked || (Date.now() - firstService.lastChecked.getTime() > 20000)) {
      this.statusService.checkAllServices();
    }
  }
}
