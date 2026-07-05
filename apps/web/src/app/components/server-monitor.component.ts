import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { interval, Subscription } from 'rxjs';
import { switchMap, startWith } from 'rxjs/operators';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { SystemMetrics } from '../models';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { GaugeCardComponent } from './gauge-card.component';

@Component({
  selector: 'app-server-monitor',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, TooltipDirective, TranslatePipe, GaugeCardComponent],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">monitor_heart</app-icon>
      <div>
        <h2 class="page-title">{{ 'sidebar.monitoring' | translate }}</h2>
        <p class="page-subtitle">
          <span class="live-badge">{{ 'monitor.live' | translate }}</span>
          {{ 'monitor.refreshRate' | translate }}
          <span *ngIf="metrics"> · {{ 'monitor.uptime' | translate }} {{ uptime(metrics.system.uptimeSeconds) }}</span>
        </p>
      </div>
      <button class="cg-btn" (click)="refresh()" style="margin-left:auto;" [cgTooltip]="'monitor.refreshNow' | translate">
        <app-icon>refresh</app-icon>
      </button>
    </div>

    <!-- Health strip -->
    <div class="health-strip" *ngIf="metrics">
      <div class="health-item">
        <app-icon style="color:#34d399;">check_circle</app-icon>
        <span>{{ 'monitor.serverOnline' | translate }}</span>
      </div>
      <div class="health-item">
        <app-icon style="color:#60a5fa;">memory</app-icon>
        <span>{{ metrics.system.nodeName }}</span>
      </div>
      <div class="health-item">
        <app-icon style="color:#a78bfa;">code</app-icon>
        <span>Elixir {{ metrics.system.elixirVersion }} / OTP {{ metrics.system.otpVersion }}</span>
      </div>
      <div class="health-item">
        <app-icon style="color:#fbbf24;">settings</app-icon>
        <span>{{ 'monitor.erlangProcs' | translate:{ count: metrics.system.processCount } }}</span>
      </div>
    </div>

    <div *ngIf="!metrics" class="cg-empty" style="padding:40px;text-align:center;">
      <app-icon style="font-size:36px;opacity:.3;">monitor_heart</app-icon>
      <p>{{ 'monitor.loading' | translate }}</p>
    </div>

    <ng-container *ngIf="metrics">

      <!-- Gauges row: CPU / RAM / Disco principal -->
      <div class="gauges-row">
        <app-gauge-card [percent]="metrics.cpu.usagePercent" unit="CPU"
          [innerPercent]="metrics.cpu.beamUsagePercent">
          <div gaugeLegend class="gauge-legend" [class]="stateOf(metrics.cpu.usagePercent)">
            <div class="legend-row">
              <span class="legend-dot outer-dot"></span>
              <span class="legend-name">{{ 'monitor.cpuUnit' | translate }}</span>
              <span class="legend-val">{{ metrics.cpu.usagePercent | number:'1.0-0' }}%</span>
            </div>
            <div class="legend-row">
              <span class="legend-dot inner-dot"></span>
              <span class="legend-name">BEAM</span>
              <span class="legend-val">{{ metrics.cpu.beamUsagePercent | number:'1.0-1' }}%</span>
            </div>
          </div>
          <div gaugeFooter class="gauge-footer cpu-cores">
            <span>{{ metrics.cpu.schedulers }}t / {{ metrics.cpu.logicalCores }}c</span>
          </div>
        </app-gauge-card>

        <app-gauge-card [percent]="metrics.memory.os.usedPercent" unit="RAM">
          <div gaugeFooter class="gauge-footer">
            <span>{{ metrics.memory.os.usedMb | number:'1.0-0' }} {{ 'monitor.mbUsed' | translate }}</span>
            <span>{{ 'monitor.of' | translate }} {{ metrics.memory.os.totalMb | number:'1.0-0' }} MB</span>
          </div>
        </app-gauge-card>

        <app-gauge-card *ngFor="let d of mainDisks"
          [percent]="d.usedPercent" [unit]="'monitor.diskUnit' | translate">
          <div gaugeFooter class="gauge-footer">
            <span>{{ d.mount }}</span>
            <span>{{ d.totalGb | number:'1.0-1' }} GB total</span>
          </div>
        </app-gauge-card>
      </div>

      <!-- Memory details + Oban -->
      <div class="panels-row">

        <!-- BEAM VM memory breakdown -->
        <div class="cg-panel" style="flex:1;">
          <div class="cg-panel-header">
            <app-icon style="opacity:.6;">memory</app-icon>
            <p class="cg-panel-title">{{ 'monitor.vmMemory' | translate }}</p>
            <p class="cg-panel-sub" style="margin-left:6px;">· {{ metrics.memory.vm.totalMb | number:'1.0-1' }} MB total</p>
          </div>
          <div class="cg-panel-body padded" style="display:flex;flex-direction:column;gap:12px;">
            <div *ngFor="let bar of vmBars" class="bar-row">
              <span class="bar-label">{{ bar.label }}</span>
              <div class="bar-track">
                <div class="bar-fill" [style.width.%]="bar.pct" [style.background]="bar.color"></div>
              </div>
              <span class="bar-value">{{ bar.mb | number:'1.0-1' }} MB</span>
            </div>
          </div>
        </div>

        <!-- Oban jobs -->
        <div class="cg-panel" style="flex:1;">
          <div class="cg-panel-header">
            <app-icon style="opacity:.6;">queue</app-icon>
            <p class="cg-panel-title">{{ 'monitor.obanQueue' | translate }}</p>
          </div>
          <div class="cg-panel-body padded" style="display:flex;flex-direction:column;gap:10px;">
            <div *ngFor="let s of obanStats" class="oban-row">
              <span class="oban-dot" [style.background]="s.color"></span>
              <span class="oban-label">{{ s.label }}</span>
              <span class="oban-value">{{ s.count }}</span>
            </div>
          </div>
        </div>

      </div>

      <!-- All disk partitions -->
      <div class="cg-panel" *ngIf="metrics.disk.length > 0">
        <div class="cg-panel-header">
          <app-icon style="opacity:.6;">storage</app-icon>
          <p class="cg-panel-title">{{ 'monitor.diskPartitions' | translate }}</p>
        </div>
        <div class="cg-panel-body">
          <div *ngFor="let d of metrics.disk" class="list-row" style="cursor:default;">
            <app-icon style="opacity:.5;flex-shrink:0;">hard_drive</app-icon>
            <div class="row-main">
              <span class="row-title">{{ d.mount }}</span>
              <div class="disk-bar-track" style="margin-top:4px;">
                <div class="disk-bar-fill" [class]="gaugeClass(d.usedPercent)"
                     [style.width.%]="d.usedPercent"></div>
              </div>
            </div>
            <span class="row-meta">{{ d.usedPercent | number:'1.0-0' }}% · {{ d.totalGb | number:'1.0-1' }} GB</span>
          </div>
        </div>
      </div>

    </ng-container>
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }

    /* Health strip */
    .health-strip {
      display: flex;
      flex-wrap: wrap;
      gap: 0;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      border-radius: 10px;
      margin-bottom: 18px;
      overflow: hidden;
    }
    .health-item {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 10px 20px;
      font-size: 13px;
      color: var(--cg-text-muted);
      border-right: 1px solid var(--cg-border);
      &:last-child { border-right: none; }
      app-icon { font-size: 16px; width: 16px; height: 16px; }
    }

    /* Gauges */
    .gauges-row {
      display: flex;
      gap: 16px;
      margin-bottom: 18px;
      flex-wrap: wrap;
    }
    /* CPU dual-ring legend (the gauge card/ring styling lives in GaugeCardComponent) */
    .gauge-legend {
      width: 100%;
      display: flex;
      flex-direction: column;
      gap: 5px;
      padding: 0 4px;
    }
    .legend-row {
      display: flex;
      align-items: center;
      gap: 7px;
      font-size: 12px;
      color: var(--cg-text-muted);
    }
    .legend-dot {
      width: 9px; height: 9px;
      border-radius: 50%;
      flex-shrink: 0;
    }
    .legend-name { flex: 1; }
    .legend-val { font-weight: 700; color: var(--cg-text); font-variant-numeric: tabular-nums; }
    .inner-dot { background: #60a5fa; }
    .outer-dot { background: var(--cg-text-muted); }
    .gauge-legend.ok    .outer-dot { background: #34d399; }
    .gauge-legend.warn  .outer-dot { background: #fbbf24; }
    .gauge-legend.danger .outer-dot { background: #f87171; }
    .legend-row:has(.inner-dot) .legend-val { color: #60a5fa; }
    .cpu-cores {
      justify-content: center;
      padding-top: 8px;
      border-top: 1px solid var(--cg-border);
    }
    .gauge-footer {
      display: flex;
      justify-content: space-between;
      width: 100%;
      font-size: 11px;
      color: var(--cg-text-muted);
    }

    /* Panels row */
    .panels-row { display: flex; gap: 18px; margin-bottom: 0; flex-wrap: wrap; }
    .panels-row .cg-panel { margin-bottom: 18px; }

    /* VM bars */
    .bar-row {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .bar-label { font-size: 12px; color: var(--cg-text-muted); width: 90px; flex-shrink: 0; }
    .bar-track {
      flex: 1;
      height: 8px;
      background: var(--cg-border);
      border-radius: 4px;
      overflow: hidden;
    }
    .bar-fill {
      height: 100%;
      border-radius: 4px;
      transition: width 0.5s ease;
    }
    .bar-value { font-size: 12px; color: var(--cg-text); width: 70px; text-align: right; flex-shrink: 0; }

    /* Oban */
    .oban-row {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 13px;
    }
    .oban-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
    .oban-label { flex: 1; color: var(--cg-text-muted); }
    .oban-value { font-weight: 700; color: var(--cg-text); font-size: 16px; min-width: 32px; text-align: right; }

    /* Disk bar */
    .disk-bar-track {
      height: 6px;
      background: var(--cg-border);
      border-radius: 3px;
      overflow: hidden;
      max-width: 400px;
    }
    .disk-bar-fill {
      height: 100%;
      border-radius: 3px;
      transition: width 0.5s ease;
      &.ok     { background: #34d399; }
      &.warn   { background: #fbbf24; }
      &.danger { background: #f87171; }
    }
  `],
})
export class ServerMonitorComponent implements OnInit, OnDestroy {
  metrics?: SystemMetrics;
  private sub?: Subscription;

  constructor(private api: ApiService, private nav: NavContextService, private i18n: TranslationService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('sidebar.monitoring') }]);
    this.sub = interval(4000).pipe(
      startWith(0),
      switchMap(() => this.api.getSystemMetrics()),
    ).subscribe(m => { this.metrics = m; this.cdr.markForCheck(); });
  }

  ngOnDestroy(): void { this.sub?.unsubscribe(); }

  refresh(): void {
    this.api.getSystemMetrics().subscribe(m => { this.metrics = m; this.cdr.markForCheck(); });
  }

  get mainDisks() {
    return this.metrics?.disk.filter(d => d.mount === '/' || d.mount === '/home') ?? [];
  }

  get vmBars() {
    if (!this.metrics) return [];
    const vm = this.metrics.memory.vm;
    const total = vm.totalMb || 1;
    return [
      { label: this.i18n.t('monitor.vm.processes'), mb: vm.processesMb, pct: (vm.processesMb / total) * 100, color: '#60a5fa' },
      { label: this.i18n.t('monitor.vm.binaries'),  mb: vm.binaryMb,    pct: (vm.binaryMb    / total) * 100, color: '#a78bfa' },
      { label: this.i18n.t('monitor.vm.code'),      mb: vm.codeMb,      pct: (vm.codeMb      / total) * 100, color: '#34d399' },
      { label: 'ETS',                               mb: vm.etsMb,       pct: (vm.etsMb       / total) * 100, color: '#fbbf24' },
    ];
  }

  get obanStats() {
    if (!this.metrics) return [];
    const o = this.metrics.oban;
    return [
      { label: this.i18n.t('monitor.oban.executing'), count: o.executing, color: '#60a5fa' },
      { label: this.i18n.t('monitor.oban.available'), count: o.available, color: '#34d399' },
      { label: this.i18n.t('monitor.oban.scheduled'), count: o.scheduled, color: '#a78bfa' },
      { label: this.i18n.t('monitor.oban.completed'), count: o.completed, color: '#6b7280' },
      { label: this.i18n.t('monitor.oban.retryable'), count: o.retryable, color: '#fbbf24' },
      { label: this.i18n.t('monitor.oban.discarded'), count: o.discarded, color: '#f87171' },
    ];
  }

  gaugeClass(pct: number): string {
    return 'gauge-card ' + this.stateOf(pct);
  }

  stateOf(pct: number): 'ok' | 'warn' | 'danger' {
    if (pct >= 85) return 'danger';
    if (pct >= 60) return 'warn';
    return 'ok';
  }

  uptime(seconds: number): string {
    if (seconds < 60) return `${seconds}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    return `${h}h ${m}m`;
  }
}
