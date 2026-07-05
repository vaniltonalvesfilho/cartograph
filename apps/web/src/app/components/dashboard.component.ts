import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { interval, Subscription } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { GraphQLService } from '../services/graphql.service';
import { DashboardMetrics } from '../graphql/types';
import { NavContextService } from '../services/nav-context.service';
import { MetricCardComponent } from './metric-card.component';
import { IconComponent } from './icon.component';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, MetricCardComponent, TranslatePipe],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">dashboard</app-icon>
      <div>
        <h2 class="page-title">{{ 'dashboard.title' | translate }}</h2>
        <p class="page-subtitle">{{ 'dashboard.subtitle' | translate }}</p>
      </div>
    </div>

    <div class="metrics-grid">
      <app-metric-card [label]="'dashboard.totalJobs' | translate"   [value]="metrics.totalTasks"    icon="grid_view"></app-metric-card>
      <app-metric-card [label]="'dashboard.groups' | translate"      [value]="metrics.totalGroups"   icon="folder"></app-metric-card>
      <app-metric-card [label]="'dashboard.projects' | translate"    [value]="metrics.totalProjects" icon="work_outline"></app-metric-card>
      <app-metric-card [label]="'dashboard.runningNow' | translate"  [value]="metrics.running"       icon="play_circle"    color="var(--cg-accent)"></app-metric-card>
      <app-metric-card [label]="'dashboard.successRate' | translate" [value]="metrics.successRate"   icon="check_circle"   color="#22c55e"></app-metric-card>
      <app-metric-card [label]="'dashboard.scheduled' | translate"   [value]="metrics.scheduled"     icon="schedule"       color="#eab308"></app-metric-card>
    </div>
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }
  `],
})
export class DashboardComponent implements OnInit, OnDestroy {
  metrics = { totalTasks: 0, totalGroups: 0, totalProjects: 0, running: 0, successRate: <string | number>'—', scheduled: 0 };

  private pollSub?: Subscription;

  constructor(private gql: GraphQLService, private nav: NavContextService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    this.nav.set([{ label: 'Servidor' }]);
    this.load();
    this.pollSub = interval(15000).pipe(switchMap(() => this.gql.dashboardMetrics())).subscribe(m => this.applyMetrics(m));
  }

  ngOnDestroy(): void { this.pollSub?.unsubscribe(); }

  private load(): void {
    this.gql.dashboardMetrics().subscribe(m => this.applyMetrics(m));
  }

  private applyMetrics(m: DashboardMetrics): void {
    this.metrics = {
      totalTasks:    m.totalTasks    ?? 0,
      totalGroups:   m.totalGroups   ?? 0,
      totalProjects: m.totalProjects ?? 0,
      running:       m.running       ?? 0,
      scheduled:     m.scheduled     ?? 0,
      successRate:   m.successRate != null ? `${m.successRate}%` : '—',
    };
    this.cdr.markForCheck();
  }
}
