import { ChangeDetectionStrategy, ChangeDetectorRef, Component, NgZone, OnDestroy, OnInit } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { Subscription } from 'rxjs';
import { ApiService } from '../services/api.service';
import { GraphQLService } from '../services/graphql.service';
import { NavContextService } from '../services/nav-context.service';
import { ExecutionLog, FlowNode, Status, StepExecution, TaskExecution } from '../models';
import { StepPipelineComponent } from './step-pipeline.component';
import { FlowGraphComponent } from './flow-graph.component';
import { GNode } from './flow-graph.model';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-execution-detail',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, DatePipe,
    IconComponent, TooltipDirective,
    StepPipelineComponent, FlowGraphComponent, TranslatePipe,
  ],
  template: `
    <!-- Header -->
    <div class="page-header" *ngIf="execution">
      <div class="exec-status-dot {{ execution.status }}"></div>
      <div>
        <h2 class="page-title">{{ 'execDetail.title' | translate:{ id: execution.id } }}</h2>
        <p class="page-subtitle">
          {{ execution.taskName }}
          &nbsp;·&nbsp;
          <span class="status-badge {{ execution.status }}">{{ execution.status }}</span>
          &nbsp;·&nbsp;
          {{ execution.startedAt ? (execution.startedAt | date:'dd/MM/yy HH:mm:ss') : '—' }}
          <ng-container *ngIf="execution.finishedAt">
            &nbsp;→&nbsp;{{ execution.finishedAt | date:'HH:mm:ss' }}
            &nbsp;({{ totalDuration() }})
          </ng-container>
        </p>
      </div>
      <div style="margin-left:auto;display:flex;gap:8px;align-items:center;">
        <button class="cg-btn cg-btn-danger" (click)="stop()" [disabled]="!isRunning()">
          <app-icon>stop</app-icon> {{ 'common.stop' | translate }}
        </button>
        <button class="cg-btn cg-btn-primary" (click)="rerun()">
          <app-icon>replay</app-icon> {{ 'execDetail.rerun' | translate }}
        </button>
      </div>
    </div>

    <!-- Flow graph with live execution overlay -->
    <div class="cg-panel" *ngIf="flow.length">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">account_tree</app-icon>
        <p class="cg-panel-title">{{ 'flow.title' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'execDetail.flowHint' | translate }}</p>
      </div>
      <div style="padding:12px 18px;">
        <app-flow-graph
          [flow]="flow"
          [statusByNode]="statusByNode"
          [selectable]="true"
          [selectedId]="selectedNodeId"
          (stepClick)="onStepClick($event)"></app-flow-graph>
      </div>
    </div>

    <!-- Pipeline de steps -->
    <div class="cg-panel" *ngIf="steps.length">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">timeline</app-icon>
        <p class="cg-panel-title">{{ 'execDetail.pipeline' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'execDetail.stepsCount' | translate:{ count: steps.length } }}</p>
      </div>
      <app-step-pipeline [steps]="steps"></app-step-pipeline>
    </div>

    <!-- Uso de agentes (tokens / custo) -->
    <div class="cg-panel" *ngIf="agentSteps.length">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">auto_awesome</app-icon>
        <p class="cg-panel-title">{{ 'agent.usageTitle' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'agent.totalUsage' | translate:{ tokens: fmtTokens(totalTokens), cost: fmtCost(totalCost) } }}</p>
      </div>
      <div class="cg-panel-body">
        <div *ngFor="let s of agentSteps" class="list-row" style="padding: 8px 16px; cursor: default;">
          <app-icon style="opacity:.5;flex-shrink:0;">auto_awesome</app-icon>
          <div class="row-main">
            <span class="row-title">{{ s.stepName }}</span>
            <span class="row-desc mono">{{ s.agentUsage?.model }}</span>
          </div>
          <span class="usage-chip mono" [cgTooltip]="'agent.tokens' | translate">
            ↑{{ fmtTokens(s.agentUsage!.inputTokens) }}
            ↓{{ fmtTokens(s.agentUsage!.outputTokens) }} tok
            <ng-container *ngIf="s.agentUsage?.estimatedCostUsd != null">· ~{{ fmtCost(s.agentUsage!.estimatedCostUsd!) }}</ng-container>
          </span>
        </div>
      </div>
    </div>

    <!-- Detalhes dos steps com erros -->
    <div class="cg-panel" *ngIf="failedSteps.length">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;color:#f87171;">error</app-icon>
        <p class="cg-panel-title">{{ 'execDetail.errors' | translate }}</p>
      </div>
      <div class="cg-panel-body">
        <div *ngFor="let s of failedSteps" class="list-row">
          <span class="status-badge FAILED">{{ s.status }}</span>
          <div class="row-main">
            <span class="row-title">{{ s.stepName }}</span>
            <span class="row-desc error-msg">{{ s.errorMessage }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Log viewer -->
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">terminal</app-icon>
        <p class="cg-panel-title">{{ 'common.logs' | translate }}</p>
        <span *ngIf="live" class="live-badge" style="margin-left:8px;">live</span>
        <span *ngIf="!live && logs.length > 0" style="font-size:12px;opacity:0.6;margin-left:8px;align-self:center;">{{ 'execDetail.history' | translate }}</span>
        <span *ngIf="filterStep" class="filter-chip" style="margin-left:auto;">
          {{ 'execDetail.filterStep' | translate:{ name: filterStep.stepName } }}
          <button class="chip-clear" (click)="clearFilter()" [cgTooltip]="'execDetail.clearFilter' | translate">✕</button>
        </span>
      </div>
      <div style="padding:12px 18px;">
        <div class="logs">
          <div *ngFor="let l of visibleLogs" [ngClass]="l.level">
            <span class="ts">{{ l.timestamp | date:'HH:mm:ss.SSS' }}</span>
            <span>{{ l.message }}</span>
          </div>
          <div *ngIf="visibleLogs.length === 0" style="color:#6b7280;">{{ 'execDetail.waitingLogs' | translate }}</div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .exec-status-dot {
      width: 14px; height: 14px; border-radius: 50%; flex-shrink: 0;
      &.RUNNING  { background: #2563eb; animation: pulse-dot 1.5s ease-in-out infinite; }
      &.SUCCESS  { background: #059669; }
      &.FAILED   { background: #dc2626; }
      &.PENDING  { background: #6b7280; }
      &.STOPPED  { background: #d97706; }
    }
    @keyframes pulse-dot {
      0%, 100% { opacity: 1; transform: scale(1); }
      50%       { opacity: 0.6; transform: scale(1.3); }
    }
    .error-msg { color: #f87171 !important; font-family: monospace; font-size: 12px; }
    .filter-chip {
      display: inline-flex; align-items: center; gap: 6px;
      font-size: 12px; padding: 2px 6px 2px 10px; border-radius: 999px;
      background: color-mix(in srgb, var(--cg-accent) 14%, transparent);
      border: 1px solid color-mix(in srgb, var(--cg-accent) 40%, transparent);
    }
    .chip-clear {
      border: none; background: transparent; cursor: pointer;
      color: inherit; font-size: 12px; line-height: 1; padding: 2px 4px;
    }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .usage-chip {
      flex-shrink: 0; font-size: 12px; padding: 3px 10px; border-radius: 999px;
      background: color-mix(in srgb, var(--cg-accent) 12%, transparent);
      border: 1px solid color-mix(in srgb, var(--cg-accent) 36%, transparent);
      color: var(--cg-text);
    }
  `],
})
export class ExecutionDetailComponent implements OnInit, OnDestroy {
  execution?: TaskExecution;
  steps: StepExecution[] = [];
  logs: ExecutionLog[] = [];
  live = false;

  flow: FlowNode[] = [];
  statusByNode: Record<string, Status> = {};
  selectedNodeId: string | null = null;
  filterStep?: StepExecution;

  private id!: number;
  private flowLoadedForTask?: number;
  private seenLogIds = new Set<number>();
  private routeSub?: Subscription;
  private logSub?: Subscription;
  private statusSub?: Subscription;
  private stepsSub?: Subscription;
  private pollTimer?: any;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private api: ApiService,
    private gql: GraphQLService,
    private nav: NavContextService,
    private zone: NgZone,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  get failedSteps(): StepExecution[] {
    return this.steps.filter(s => s.status === 'FAILED' && s.errorMessage);
  }

  get agentSteps(): StepExecution[] {
    return this.steps.filter(s => !!s.agentUsage);
  }

  get totalTokens(): number {
    return this.agentSteps.reduce(
      (sum, s) => sum + (s.agentUsage!.inputTokens || 0) + (s.agentUsage!.outputTokens || 0), 0);
  }

  get totalCost(): number {
    return this.agentSteps.reduce((sum, s) => sum + (s.agentUsage!.estimatedCostUsd || 0), 0);
  }

  fmtTokens(n: number): string {
    if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
    return String(n);
  }

  fmtCost(usd: number): string {
    return `$${usd.toFixed(usd < 0.01 ? 4 : 3)}`;
  }

  get visibleLogs(): ExecutionLog[] {
    if (!this.filterStep) return this.logs;
    const stepId = this.filterStep.id;
    return this.logs.filter(l => l.stepExecutionId === stepId);
  }

  ngOnInit(): void {
    // React to :id changes so navigating to a re-run (same component, new param)
    // re-initialises without a full page reload.
    this.routeSub = this.route.paramMap.subscribe(pm => this.load(Number(pm.get('id'))));
    this.pollTimer = setInterval(() => {
      if (this.execution && this.isRunning()) this.refresh();
    }, 3000);
  }

  ngOnDestroy(): void {
    this.routeSub?.unsubscribe();
    this.logSub?.unsubscribe();
    this.statusSub?.unsubscribe();
    this.stepsSub?.unsubscribe();
    if (this.pollTimer) clearInterval(this.pollTimer);
  }

  private load(id: number): void {
    this.id = id;
    // Reset per-execution state and re-open the live subscriptions for the new id.
    this.execution = undefined;
    this.steps = [];
    this.logs = [];
    this.seenLogIds = new Set<number>();
    this.live = false;
    this.statusByNode = {};
    this.selectedNodeId = null;
    this.filterStep = undefined;
    this.logSub?.unsubscribe();
    this.statusSub?.unsubscribe();
    this.stepsSub?.unsubscribe();

    this.nav.set([{ label: this.i18n.t('execDetail.title', { id }) }]);
    this.cdr.markForCheck();
    this.refresh();
    this.loadInitialLogs();
    this.openSubscriptions();
  }

  isRunning(): boolean {
    return this.execution?.status === 'RUNNING' || this.execution?.status === 'PENDING';
  }

  totalDuration(): string {
    if (!this.execution?.startedAt || !this.execution?.finishedAt) return '';
    const ms = new Date(this.execution.finishedAt).getTime() - new Date(this.execution.startedAt).getTime();
    return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
  }

  private refresh(): void {
    this.api.getExecution(this.id).subscribe((d) => {
      this.execution = d.execution;
      this.steps = d.steps;
      this.rebuildStatusByNode();
      this.loadFlow(d.execution.taskDefinitionId);
      this.cdr.markForCheck();
    });
  }

  // The flow graph comes from the CURRENT task DSL: if the job changed since
  // this execution ran, some steps may not correlate (they just get no overlay).
  private loadFlow(taskId: number): void {
    if (!taskId || this.flowLoadedForTask === taskId) return;
    this.flowLoadedForTask = taskId;
    this.api.taskFlow(taskId).subscribe({
      next: (flow) => { this.flow = flow; this.cdr.markForCheck(); },
      error: () => { /* task deleted / no access: panel stays hidden */ },
    });
  }

  private rebuildStatusByNode(): void {
    const map: Record<string, Status> = {};
    for (const s of this.steps) {
      if (s.flowNodeId) map[s.flowNodeId] = s.status;
    }
    this.statusByNode = map;
  }

  private loadInitialLogs(): void {
    this.api.getLogs(this.id).subscribe((logs) => {
      for (const l of logs) {
        if (!this.seenLogIds.has(l.id)) {
          this.seenLogIds.add(l.id);
          this.logs.push(l);
        }
      }
      this.cdr.markForCheck();
    });
  }

  private openSubscriptions(): void {
    const idStr = String(this.id);

    this.logSub = this.gql.subscribeExecutionLogs(idStr).subscribe({
      next: (log) => {
        this.zone.run(() => {
          this.live = true;
          const lid = Number(log.id);
          if (!this.seenLogIds.has(lid)) {
            this.seenLogIds.add(lid);
            this.logs.push({
              id: lid,
              executionId: this.id,
              stepExecutionId: log.stepExecutionId != null ? Number(log.stepExecutionId) : undefined,
              level: log.level ?? '',
              message: log.message ?? '',
              timestamp: log.timestamp ?? '',
            });
          }
          this.cdr.markForCheck();
        });
      },
      error: () => this.zone.run(() => { this.live = false; this.cdr.markForCheck(); }),
    });

    // Live per-step transitions paint the flow graph; the 3s poll stays as a
    // fallback for missed events (reconnect, page opened mid-run).
    this.stepsSub = this.gql.subscribeExecutionSteps(idStr).subscribe({
      next: (s) => {
        this.zone.run(() => {
          this.live = true;
          this.upsertStep({
            id: Number(s.id),
            executionId: this.id,
            stepName: s.stepName ?? '',
            stepOrder: s.stepOrder ?? 0,
            status: (s.status as Status) ?? 'PENDING',
            startedAt: s.startedAt ?? undefined,
            finishedAt: s.finishedAt ?? undefined,
            errorMessage: s.errorMessage ?? undefined,
            flowNodeId: s.flowNodeId ?? null,
            agentUsage: s.agentUsage
              ? {
                  model: s.agentUsage.model ?? '',
                  inputTokens: s.agentUsage.inputTokens ?? 0,
                  outputTokens: s.agentUsage.outputTokens ?? 0,
                  cacheReadInputTokens: s.agentUsage.cacheReadInputTokens ?? undefined,
                  estimatedCostUsd: s.agentUsage.estimatedCostUsd ?? undefined,
                  stopReason: s.agentUsage.stopReason ?? undefined,
                  durationMs: s.agentUsage.durationMs ?? undefined,
                }
              : null,
          });
          this.cdr.markForCheck();
        });
      },
    });

    this.statusSub = this.gql.subscribeExecutionStatus(idStr).subscribe({
      next: (exec) => {
        this.zone.run(() => {
          if (this.execution) {
            this.execution = {
              ...this.execution,
              status: (exec.status as Status) ?? this.execution.status,
              startedAt: exec.startedAt ?? this.execution.startedAt,
              finishedAt: exec.finishedAt ?? this.execution.finishedAt,
            };
          }
          if (!this.isRunning()) this.refresh();
          this.cdr.markForCheck();
        });
      },
    });
  }

  private upsertStep(step: StepExecution): void {
    const i = this.steps.findIndex(s => s.id === step.id);
    this.steps = i >= 0
      ? this.steps.map(s => (s.id === step.id ? step : s))
      : [...this.steps, step].sort((a, b) => a.stepOrder - b.stepOrder);
    this.rebuildStatusByNode();
  }

  onStepClick(node: GNode): void {
    if (this.selectedNodeId === node.id) {
      this.clearFilter();
      return;
    }
    const step = this.steps.find(s => s.flowNodeId === node.id);
    if (!step) return; // node not reached in this run — nothing to filter
    this.selectedNodeId = node.id;
    this.filterStep = step;
  }

  clearFilter(): void {
    this.selectedNodeId = null;
    this.filterStep = undefined;
  }

  stop(): void {
    this.api.stop(this.id).subscribe(() => this.refresh());
  }

  rerun(): void {
    if (!this.execution) return;
    this.api.runTask(this.execution.taskDefinitionId).subscribe((res) => {
      // The paramMap subscription re-initialises the view for the new execution.
      this.router.navigate(['/executions', res.executionId]);
    });
  }
}
