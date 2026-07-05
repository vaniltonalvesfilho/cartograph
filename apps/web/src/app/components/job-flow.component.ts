import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { CopyIdComponent } from './copy-id.component';
import { TranslatePipe } from '../services/translate.pipe';
import { FlowNode } from '../models';

/**
 * Recursive renderer for a job's execution flow (GET /tasks/:id/flow).
 *
 * Steps render as cards; an inlined sub-job (`use "<code>"`) renders as a tinted
 * container with the sub-job's own flow nested inside (and a link to open it);
 * if/else renders as two labelled branches. The component references its own
 * `app-job-flow` selector to recurse — standalone self-reference needs no import.
 */
@Component({
  selector: 'app-job-flow',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink, IconComponent, TooltipDirective,
    CopyIdComponent, TranslatePipe,
  ],
  template: `
    <div class="flow">
      <ng-container *ngFor="let node of nodes; let last = last">

        <!-- Step -->
        <div *ngIf="node.kind === 'step'" class="flow-card step">
          <app-icon class="card-icon">{{ stepIcon(node.name) }}</app-icon>
          <div class="card-body">
            <span class="card-title">{{ node.name }}</span>
            <span *ngIf="paramSummary(node.params) as ps" class="card-sub mono">{{ ps }}</span>
          </div>
        </div>

        <!-- Inlined sub-job -->
        <div *ngIf="node.kind === 'job'" class="flow-job">
          <div class="job-header">
            <app-icon class="job-icon">account_tree</app-icon>
            <span class="job-name">{{ node.name }}</span>
            <app-copy-id [value]="node.ref"></app-copy-id>
            <span *ngIf="node.cycle" class="cycle-badge"
                  [cgTooltip]="'flow.cycleTooltip' | translate">
              <app-icon>sync_problem</app-icon>{{ 'flow.cycle' | translate }}
            </span>
            <a *ngIf="node.taskId" [routerLink]="['/tasks', node.taskId]"
               class="cg-icon-btn job-open"
               [cgTooltip]="'flow.openJob' | translate">
              <app-icon>open_in_new</app-icon>
            </a>
          </div>
          <div *ngIf="node.steps.length" class="job-body">
            <app-job-flow [nodes]="node.steps"></app-job-flow>
          </div>
          <div *ngIf="!node.steps.length && !node.cycle" class="job-body empty">
            {{ 'flow.emptyJob' | translate }}
          </div>
        </div>

        <!-- If / else -->
        <div *ngIf="node.kind === 'if'" class="flow-if">
          <div class="if-header">
            <app-icon>call_split</app-icon>
            <code class="mono">if {{ node.condition }}</code>
          </div>
          <div class="branches">
            <div class="branch then">
              <span class="branch-label">{{ 'flow.then' | translate }}</span>
              <app-job-flow *ngIf="node.then.length" [nodes]="node.then"></app-job-flow>
              <div *ngIf="!node.then.length" class="branch-empty">—</div>
            </div>
            <div *ngIf="node.else.length" class="branch else">
              <span class="branch-label">{{ 'flow.else' | translate }}</span>
              <app-job-flow [nodes]="node.else"></app-job-flow>
            </div>
          </div>
        </div>

        <!-- Unresolved / forbidden ref -->
        <div *ngIf="node.kind === 'job_error'" class="flow-card error"
             [cgTooltip]="'flow.unresolvedTooltip' | translate">
          <app-icon class="card-icon">error_outline</app-icon>
          <div class="card-body">
            <span class="card-title">{{ 'flow.unresolved' | translate }}</span>
            <span class="card-sub mono">use "{{ node.ref }}"</span>
          </div>
        </div>

        <!-- Connector between sibling nodes -->
        <div *ngIf="!last" class="connector"><app-icon>arrow_downward</app-icon></div>

      </ng-container>
    </div>
  `,
  styles: [`
    .flow { display: flex; flex-direction: column; align-items: stretch; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }

    .flow-card {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 10px 12px;
      border-radius: 10px;
      background: var(--cg-surface-2, rgba(127,127,127,0.08));
      border: 1px solid var(--cg-border, rgba(127,127,127,0.2));
    }
    .flow-card.error {
      background: #7f1d1d22;
      border-color: #f8717155;
      color: #f87171;
    }
    .card-icon { color: var(--cg-accent); flex: 0 0 auto; }
    .flow-card.error .card-icon { color: #f87171; }
    .card-body { display: flex; flex-direction: column; min-width: 0; }
    .card-title { font-weight: 600; font-size: 14px; }
    .card-sub { font-size: 12px; color: var(--cg-text-muted); overflow: hidden; text-overflow: ellipsis; }

    .connector {
      display: flex;
      justify-content: center;
      color: var(--cg-text-muted);
      opacity: 0.55;
    }
    .connector app-icon { font-size: 18px; width: 18px; height: 18px; }

    .flow-job {
      border: 1px solid var(--cg-accent);
      border-radius: 12px;
      overflow: hidden;
      background: color-mix(in srgb, var(--cg-accent) 6%, transparent);
    }
    .job-header {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 10px;
      background: color-mix(in srgb, var(--cg-accent) 12%, transparent);
      border-bottom: 1px solid color-mix(in srgb, var(--cg-accent) 30%, transparent);
    }
    .job-icon { color: var(--cg-accent); }
    .job-name { font-weight: 700; font-size: 13px; }
    .job-open { margin-left: auto; width: 32px; height: 32px; line-height: 32px; }
    .job-open app-icon { font-size: 18px; width: 18px; height: 18px; }
    .cycle-badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 10px;
      font-weight: 600;
      padding: 1px 8px 1px 5px;
      border-radius: 10px;
      background: #78350f33;
      color: #fbbf24;
    }
    .cycle-badge app-icon { font-size: 12px; width: 12px; height: 12px; }
    .job-body { padding: 12px; }
    .job-body.empty { font-size: 12px; color: var(--cg-text-muted); font-style: italic; }

    .flow-if {
      border: 1px dashed var(--cg-border, rgba(127,127,127,0.35));
      border-radius: 12px;
      padding: 8px;
    }
    .if-header { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
    .if-header app-icon { color: #a855f7; }
    .if-header code { font-size: 12.5px; }
    .branches { display: flex; gap: 12px; flex-wrap: wrap; }
    .branch {
      flex: 1 1 240px;
      min-width: 0;
      border-radius: 10px;
      padding: 8px;
      background: var(--cg-surface-2, rgba(127,127,127,0.06));
    }
    .branch-label {
      display: inline-block;
      font-size: 10px;
      font-weight: 700;
      letter-spacing: 0.4px;
      text-transform: uppercase;
      margin-bottom: 6px;
      color: #34d399;
    }
    .branch.else .branch-label { color: #fb923c; }
    .branch-empty { color: var(--cg-text-muted); font-size: 12px; }
  `],
})
export class JobFlowComponent {
  @Input() nodes: FlowNode[] = [];

  /** Compact one-line summary of a step's params: key "value" · key 2. */
  paramSummary(params: Record<string, unknown>): string {
    return Object.entries(params || {})
      .map(([k, v]) => `${k} ${typeof v === 'string' ? `"${v}"` : v}`)
      .join(' · ');
  }

  stepIcon(name: string): string {
    const map: Record<string, string> = {
      readDirectory: 'folder_open',
      filter: 'filter_alt',
      transform: 'auto_fix_high',
      writeOutput: 'save',
    };
    return map[name] ?? 'bolt';
  }
}
