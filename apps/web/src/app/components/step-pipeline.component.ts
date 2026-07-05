import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { StepExecution, Status } from '../models';
import { TranslationService } from '../services/translation.service';

@Component({
  selector: 'app-step-pipeline',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, TooltipDirective],
  template: `
    <div class="pipeline" *ngIf="steps.length > 0">
      <ng-container *ngFor="let s of steps; let last = last">
        <div class="pipe-node {{ s.status }}"
             [class.pulse]="s.status === 'RUNNING'"
             [cgTooltip]="tooltip(s)">
          <app-icon class="pipe-icon">{{ icon(s.status) }}</app-icon>
          <span class="pipe-label">{{ s.stepName }}</span>
          <span *ngIf="dur(s)" class="pipe-dur">{{ dur(s) }}</span>
        </div>
        <div *ngIf="!last" class="pipe-arrow">
          <app-icon>arrow_forward</app-icon>
        </div>
      </ng-container>
    </div>
  `,
  styles: [`
    .pipeline {
      display: flex;
      align-items: center;
      gap: 0;
      overflow-x: auto;
      padding: 16px 18px;
      flex-wrap: wrap;
      gap: 4px;
    }
    .pipe-node {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 4px;
      padding: 8px 12px;
      border-radius: 8px;
      border: 2px solid transparent;
      min-width: 80px;
      cursor: default;
      transition: transform 0.12s;
    }
    .pipe-node:hover { transform: translateY(-2px); }
    .pipe-node.PENDING  { background:#1f2430; border-color:#374151; color:#9ca3af; }
    .pipe-node.RUNNING  { background:#1e3a8a22; border-color:#2563eb; color:#93c5fd; }
    .pipe-node.SUCCESS  { background:#064e3b22; border-color:#059669; color:#6ee7b7; }
    .pipe-node.FAILED   { background:#7f1d1d22; border-color:#dc2626; color:#fca5a5; }
    .pipe-node.STOPPED  { background:#78350f22; border-color:#d97706; color:#fcd34d; }
    .pipe-node.SKIPPED  { background:#1f243022; border-color:#374151; color:#6b7280; }

    .pipe-icon { font-size:18px; width:18px; height:18px; }

    .pipe-label {
      font-size: 11px;
      font-weight: 600;
      text-align: center;
      max-width: 90px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .pipe-dur {
      font-size: 10px;
      opacity: 0.7;
      font-family: monospace;
    }
    .pipe-arrow {
      display: flex;
      align-items: center;
      color: var(--cg-text-muted);
      opacity: 0.4;
      padding: 0 2px;
    }
    .pipe-arrow app-icon { font-size: 16px; width: 16px; height: 16px; }

    @keyframes pulse-ring {
      0%   { box-shadow: 0 0 0 0 rgba(37,99,235,0.5); }
      70%  { box-shadow: 0 0 0 8px rgba(37,99,235,0); }
      100% { box-shadow: 0 0 0 0 rgba(37,99,235,0); }
    }
    .pipe-node.pulse { animation: pulse-ring 1.5s ease-out infinite; }
  `],
})
export class StepPipelineComponent {
  @Input() steps: StepExecution[] = [];

  constructor(private i18n: TranslationService) {}

  icon(status: Status): string {
    const map: Record<Status, string> = {
      PENDING: 'radio_button_unchecked',
      RUNNING: 'pending',
      SUCCESS: 'check_circle',
      FAILED: 'cancel',
      STOPPED: 'stop_circle',
      SKIPPED: 'skip_next',
    };
    return map[status] ?? 'help_outline';
  }

  dur(s: StepExecution): string {
    if (!s.startedAt || !s.finishedAt) return '';
    const ms = new Date(s.finishedAt).getTime() - new Date(s.startedAt).getTime();
    return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
  }

  tooltip(s: StepExecution): string {
    const parts = [`#${s.stepOrder} ${s.stepName}`, `${this.i18n.t('stepPipeline.status')}: ${s.status}`];
    if (s.startedAt) parts.push(`${this.i18n.t('stepPipeline.start')}: ${new Date(s.startedAt).toLocaleTimeString()}`);
    if (s.errorMessage) parts.push(`${this.i18n.t('stepPipeline.error')}: ${s.errorMessage}`);
    return parts.join('\n');
  }
}
