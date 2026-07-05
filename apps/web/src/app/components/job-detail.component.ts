import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { FlowNode, TaskDefinition } from '../models';
import { CopyIdComponent } from './copy-id.component';
import { JobFlowComponent } from './job-flow.component';
import { FlowGraphComponent } from './flow-graph.component';
import { ExecutionHistoryComponent } from './execution-history.component';
import { IdentIconComponent } from './ident-icon.component';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { extractApiError } from '../utils/http-error.util';

@Component({
  selector: 'app-job-detail',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink,
    IconComponent, TooltipDirective,
    CopyIdComponent, JobFlowComponent, FlowGraphComponent, ExecutionHistoryComponent, IdentIconComponent, TranslatePipe,
  ],
  template: `
    <div *ngIf="task" class="page-header">
      <app-ident-icon [name]="task.name" [size]="48"></app-ident-icon>
      <div style="min-width:0;">
        <h2 class="page-title">{{ task.name }}</h2>
        <div class="header-meta">
          <app-copy-id *ngIf="task.code" [value]="task.code"></app-copy-id>
          <span *ngIf="task.cron" class="status-badge PENDING" style="font-size:10px;">
            <app-icon style="font-size:11px;width:11px;height:11px;">schedule</app-icon>{{ task.cron }}
          </span>
        </div>
        <p *ngIf="task.description" class="page-description">{{ task.description }}</p>
      </div>
      <div class="header-actions">
        <span *ngIf="task.can?.run" [cgTooltip]="runTooltip(task)">
          <button class="cg-btn cg-btn-primary" (click)="run()" [disabled]="!runnable(task)">
            <app-icon>play_arrow</app-icon> {{ 'common.run' | translate }}
          </button>
        </span>
        <a *ngIf="task.can?.edit" [routerLink]="['/tasks', task.id, 'edit']" class="cg-btn">
          <app-icon>edit</app-icon> {{ 'common.edit' | translate }}
        </a>
      </div>
    </div>

    <div class="cg-panel" *ngIf="task">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">account_tree</app-icon>
        <p class="cg-panel-title">{{ 'flow.title' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'flow.subtitle' | translate }}</p>
        <div class="view-toggle" style="margin-left:auto;">
          <button class="cg-tab" [class.active]="view === 'graph'" (click)="view = 'graph'"
                  [cgTooltip]="'flow.viewGraph' | translate">
            <app-icon>hub</app-icon>
          </button>
          <button class="cg-tab" [class.active]="view === 'list'" (click)="view = 'list'"
                  [cgTooltip]="'flow.viewList' | translate">
            <app-icon>format_list_bulleted</app-icon>
          </button>
        </div>
      </div>
      <div class="cg-panel-body padded">
        <div *ngIf="loadingFlow" class="flow-loading">
          <span class="cg-spinner"></span>
        </div>
        <p *ngIf="flowError" class="flow-error">{{ flowError }}</p>
        <ng-container *ngIf="!loadingFlow && !flowError">
          <app-flow-graph *ngIf="view === 'graph' && flow.length" [flow]="flow"></app-flow-graph>
          <app-job-flow *ngIf="view === 'list' && flow.length" [nodes]="flow"></app-job-flow>
          <div *ngIf="flow.length === 0" class="cg-empty">{{ 'flow.emptyJob' | translate }}</div>
        </ng-container>
      </div>
    </div>

    <app-execution-history *ngIf="task" [taskId]="task.id"></app-execution-history>

    <div *ngIf="!task && !loading" style="padding: 32px; text-align: center; opacity: 0.5;">
      {{ 'taskEdit.notFound' | translate }}
    </div>
  `,
  styles: [`
    .header-meta { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin: 4px 0; }
    .header-actions { margin-left: auto; display: flex; gap: 8px; align-items: center; }
    .padded { padding: 16px; }
    .flow-loading { display: flex; justify-content: center; padding: 24px; }
    .flow-error { color: #e5484d; font-size: 13px; }
    .view-toggle { display: flex; }
    .view-toggle .cg-tab { padding: 4px 10px; }
  `],
})
export class JobDetailComponent implements OnInit {
  task?: TaskDefinition;
  flow: FlowNode[] = [];
  view: 'graph' | 'list' = 'graph';
  loading = true;
  loadingFlow = true;
  flowError = '';

  constructor(
    private api: ApiService,
    private route: ActivatedRoute,
    private router: Router,
    private nav: NavContextService,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.nav.set([{ label: this.i18n.t('sidebar.allJobs'), link: ['/tasks'] }, { label: this.i18n.t('jobDetail.title') }]);

    this.api.listTasks().subscribe(tasks => {
      this.loading = false;
      this.task = tasks.find(t => t.id === id);
      if (this.task) this.nav.set([{ label: this.i18n.t('sidebar.allJobs'), link: ['/tasks'] }, { label: this.task.name }]);
      this.cdr.markForCheck();
    });

    this.api.taskFlow(id).subscribe({
      next: nodes => { this.flow = nodes; this.loadingFlow = false; this.cdr.markForCheck(); },
      error: err => { this.flowError = extractApiError(err, this.i18n.t('flow.loadError')); this.loadingFlow = false; this.cdr.markForCheck(); },
    });
  }

  released(t: TaskDefinition): boolean {
    return !t.releaseAt || new Date(t.releaseAt).getTime() <= Date.now();
  }

  archived(t: TaskDefinition): boolean {
    return !!t.archiveAt && new Date(t.archiveAt).getTime() <= Date.now();
  }

  runnable(t: TaskDefinition): boolean {
    return this.released(t) && !this.archived(t);
  }

  runTooltip(t: TaskDefinition): string {
    if (!this.released(t)) return this.i18n.t('tasks.notReleasedTooltip', { date: new Date(t.releaseAt!).toLocaleString() });
    if (this.archived(t)) return this.i18n.t('tasks.archivedTooltip', { date: new Date(t.archiveAt!).toLocaleString() });
    return '';
  }

  run(): void {
    if (!this.task || !this.runnable(this.task)) return;
    this.api.runTask(this.task.id).subscribe(res => this.router.navigate(['/executions', res.executionId]));
  }
}
