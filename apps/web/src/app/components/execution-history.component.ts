import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnChanges, OnInit, SimpleChanges } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { ApiService } from '../services/api.service';
import { TaskExecution } from '../models';
import { TranslatePipe } from '../services/translate.pipe';

/**
 * Per-job execution history. Lists every run of a task — manual and scheduled
 * (cron) alike — newest first, with a badge showing how each was triggered.
 */
@Component({
  selector: 'app-execution-history',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, DatePipe, RouterLink,
    IconComponent, TooltipDirective, TranslatePipe,
  ],
  template: `
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">history</app-icon>
        <p class="cg-panel-title">{{ 'execHistory.title' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">· {{ 'execHistory.subtitle' | translate:{ count: executions.length } }}</p>
        <span class="spacer"></span>
        <button class="cg-icon-btn" (click)="reload()" [cgTooltip]="'execHistory.refresh' | translate">
          <app-icon>refresh</app-icon>
        </button>
      </div>
      <div class="cg-panel-body">
        <div *ngIf="executions.length === 0" class="cg-empty">
          {{ 'execHistory.empty' | translate }}
        </div>
        <a *ngFor="let e of executions" [routerLink]="['/executions', e.id]" class="list-row">
          <span class="status-badge {{ e.status }}">{{ e.status }}</span>
          <div class="row-main">
            <span class="row-title">
              #{{ e.id }}
              <span class="trigger-badge" [class.cron]="e.trigger === 'cron'">
                <app-icon>{{ e.trigger === 'cron' ? 'schedule' : 'play_arrow' }}</app-icon>
                {{ (e.trigger === 'cron' ? 'trigger.cron' : 'trigger.manual') | translate }}
              </span>
            </span>
            <span class="row-desc">{{ e.startedAt ? (e.startedAt | date:'dd/MM/yy HH:mm:ss') : '—' }}</span>
          </div>
          <span class="row-meta">{{ duration(e) }}</span>
          <app-icon class="row-arrow">chevron_right</app-icon>
        </a>
      </div>
    </div>
  `,
  styles: [`
    .spacer { flex: 1 1 auto; }
    .trigger-badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 10px;
      font-weight: 600;
      padding: 1px 8px 1px 5px;
      border-radius: 10px;
      margin-left: 8px;
      vertical-align: middle;
      background: #37415133;
      color: var(--cg-text-muted);
      letter-spacing: 0.2px;
    }
    .trigger-badge.cron { background: #1e3a8a33; color: #60a5fa; }
    .trigger-badge app-icon { font-size: 12px; width: 12px; height: 12px; }
  `],
})
export class ExecutionHistoryComponent implements OnInit, OnChanges {
  @Input() taskId!: number;

  executions: TaskExecution[] = [];

  constructor(private api: ApiService, private cdr: ChangeDetectorRef) {}

  ngOnInit(): void { this.reload(); }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['taskId'] && !changes['taskId'].firstChange) {
      this.executions = [];
      this.reload();
    }
  }

  reload(): void {
    if (this.taskId == null) return;
    this.api.listExecutions(this.taskId).subscribe(execs => {
      this.executions = execs;
      this.cdr.markForCheck();
    });
  }

  duration(e: TaskExecution): string {
    if (!e.startedAt || !e.finishedAt) return '';
    const ms = new Date(e.finishedAt).getTime() - new Date(e.startedAt).getTime();
    return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
  }
}
