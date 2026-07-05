import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { Dialog } from '@angular/cdk/dialog';
import { forkJoin, of } from 'rxjs';
import { catchError } from 'rxjs/operators';
import { ApiService } from '../services/api.service';
import { AuthService } from '../services/auth.service';
import { NavContextService, Crumb } from '../services/nav-context.service';
import { DataSource, Group, Project, TaskDefinition, TaskExecution } from '../models';
import { IdentIconComponent } from './ident-icon.component';
import { JobGraphComponent } from './job-graph.component';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { MembersPanelComponent } from './members-panel.component';
import { CopyIdComponent } from './copy-id.component';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-project-tasks',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, DatePipe, RouterLink,
    IconComponent, TooltipDirective,
    IdentIconComponent, JobGraphComponent, MembersPanelComponent, CopyIdComponent, TranslatePipe,
  ],
  template: `
    <div class="page-header" *ngIf="project">
      <app-ident-icon [name]="project.name" [size]="48"></app-ident-icon>
      <div>
        <h2 class="page-title">{{ project.name }}</h2>
        <p class="page-subtitle">{{ 'projectTasks.subtitle' | translate:{ jobs: tasks.length, execs: recentExecutions.length } }}</p>
        <p *ngIf="project.description" class="page-description">{{ project.description }}</p>
      </div>
      <a *ngIf="project.can?.create" routerLink="/tasks/new" [queryParams]="{ projectId: project.id }"
         class="cg-btn cg-btn-primary" style="margin-left: auto;">
        <app-icon>add</app-icon> {{ 'tasks.new' | translate }}
      </a>
    </div>

    <!-- Dependency graph -->
    <div class="cg-panel" *ngIf="tasks.length > 1">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">account_tree</app-icon>
        <p class="cg-panel-title">{{ 'tasks.depGraph' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;" [innerHTML]="'tasks.depGraphHintShort' | translate"></p>
      </div>
      <app-job-graph [tasks]="tasks"></app-job-graph>
    </div>

    <!-- Jobs -->
    <div class="cg-panel">
      <div class="cg-tabs">
        <button class="cg-tab" [class.active]="tab === 0" (click)="tab = 0">
          <app-icon class="tab-icon">grid_view</app-icon>{{ 'tasks.activeTab' | translate }} ({{ activeTasks.length }})
        </button>
        <button class="cg-tab" [class.active]="tab === 1" (click)="tab = 1">
          <app-icon class="tab-icon">inventory_2</app-icon>{{ 'tasks.archivedTab' | translate }} ({{ archivedTasks.length }})
        </button>
      </div>
      <div class="cg-panel-body" *ngIf="tab === 0">
        <ng-container *ngTemplateOutlet="jobList; context: { list: activeTasks, emptyKey: 'projectTasks.emptyJobs' }"></ng-container>
      </div>
      <div class="cg-panel-body" *ngIf="tab === 1">
        <ng-container *ngTemplateOutlet="jobList; context: { list: archivedTasks, emptyKey: 'tasks.emptyArchived' }"></ng-container>
      </div>
    </div>

    <ng-template #jobList let-list="list" let-emptyKey="emptyKey">
      <div *ngIf="list.length === 0" class="cg-empty">{{ emptyKey | translate }}</div>
      <div *ngFor="let t of list" class="list-row">
        <app-ident-icon [name]="t.name" [size]="32"></app-ident-icon>
        <div class="row-main">
          <span class="row-title-line">
            <a class="row-title" [routerLink]="['/tasks', t.id]">{{ t.name }}</a>
            <app-copy-id *ngIf="t.code" class="row-code" [value]="t.code"></app-copy-id>
          </span>
          <span class="row-desc">
            <span *ngIf="t.cron" class="status-badge PENDING" style="font-size:10px;">
              <app-icon style="font-size:11px;width:11px;height:11px;">schedule</app-icon>{{ t.cron }}
            </span>
            <span *ngIf="!t.cron">{{ 'tasks.manual' | translate }}</span>
            <span *ngIf="t.releaseAt" class="release-badge" [class.upcoming]="!released(t)"
                  [cgTooltip]="'tasks.releaseTooltip' | translate:{ date: (t.releaseAt | date:'dd/MM/yy HH:mm') }">
              <app-icon>rocket_launch</app-icon>{{ 'tasks.release' | translate }} · {{ t.releaseAt | date:'dd/MM/yy HH:mm' }}
            </span>
            <span *ngIf="t.archiveAt" class="archive-badge" [class.archived]="archived(t)"
                  [cgTooltip]="(archived(t) ? 'tasks.archivedTooltip' : 'tasks.archiveTooltip') | translate:{ date: (t.archiveAt | date:'dd/MM/yy HH:mm') }">
              <app-icon>{{ archived(t) ? 'inventory_2' : 'event_busy' }}</app-icon>{{ (archived(t) ? 'tasks.archived' : 'tasks.archive') | translate }} · {{ t.archiveAt | date:'dd/MM/yy HH:mm' }}
            </span>
          </span>
        </div>
        <div class="row-actions">
          <span *ngIf="t.can?.run" [cgTooltip]="runTooltip(t)">
            <button class="cg-btn cg-btn-primary" (click)="run(t)" [disabled]="!runnable(t)">
              <app-icon>play_arrow</app-icon> {{ 'common.run' | translate }}
            </button>
          </span>
          <a *ngIf="t.can?.edit" [routerLink]="['/tasks', t.id, 'edit']" class="cg-btn" [cgTooltip]="'common.edit' | translate">
            <app-icon>edit</app-icon>
          </a>
          <button *ngIf="t.can?.delete" class="cg-btn cg-btn-danger" (click)="remove(t)" [cgTooltip]="'common.delete' | translate">
            <app-icon>delete</app-icon>
          </button>
        </div>
      </div>
    </ng-template>

    <!-- Membros -->
    <app-members-panel *ngIf="project" subjectType="project" [subjectId]="project.id"></app-members-panel>

    <!-- Fontes de dados -->
    <div class="cg-panel" *ngIf="dataSources.length > 0 || isAdmin()">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">storage</app-icon>
        <p class="cg-panel-title">{{ 'dataSources.projectDataSources' | translate }}</p>
        <a *ngIf="isAdmin()" routerLink="/admin/data-sources" class="cg-btn" style="margin-left:auto;font-size:12px;">
          <app-icon>settings</app-icon> {{ 'common.manage' | translate }}
        </a>
      </div>
      <div class="cg-panel-body">
        <div *ngIf="dataSources.length === 0" class="cg-empty">
          {{ 'dataSources.projectEmpty' | translate }}
          <span *ngIf="isAdmin()">&nbsp;{{ 'dataSources.assignFromAdmin' | translate }}</span>
        </div>
        <div *ngFor="let ds of dataSources" class="list-row" style="padding: 8px 16px;">
          <div class="ds-icon-small" [class.mysql]="ds.adapter==='mysql'" [class.postgres]="ds.adapter==='postgres'">
            <app-icon>{{ ds.adapter === 'mysql' ? 'table_chart' : 'dns' }}</app-icon>
          </div>
          <div class="row-main">
            <span class="row-title-line">
              <span class="row-title">{{ ds.name }}</span>
              <span class="adapter-badge {{ ds.adapter }}">{{ ds.adapter }}</span>
              <code class="slug-chip">{{ ds.slug }}</code>
            </span>
            <span class="row-desc">{{ ds.host }}:{{ ds.port }} / {{ ds.databaseName }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Recent executions -->
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">history</app-icon>
        <p class="cg-panel-title">{{ 'projectTasks.recentActivity' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'projectTasks.recentActivityHint' | translate }}</p>
      </div>
      <div class="cg-panel-body">
        <div *ngIf="recentExecutions.length === 0" class="cg-empty">
          {{ 'projectTasks.emptyExecs' | translate }}
        </div>
        <a *ngFor="let e of recentExecutions" [routerLink]="['/executions', e.id]" class="list-row">
          <span class="status-badge {{ e.status }}">{{ e.status }}</span>
          <div class="row-main">
            <span class="row-title">{{ e.taskName }}</span>
            <span class="row-desc">#{{ e.id }} · {{ e.startedAt ? (e.startedAt | date:'dd/MM HH:mm:ss') : '—' }}</span>
          </div>
          <span class="row-meta">{{ duration(e) }}</span>
          <app-icon class="row-arrow">chevron_right</app-icon>
        </a>
      </div>
    </div>
  `,
  styles: [`
    .row-title-line { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    a.row-title { color: inherit; text-decoration: none; cursor: pointer; }
    a.row-title:hover { text-decoration: underline; }
    .tab-icon { font-size: 18px; width: 18px; height: 18px; margin-right: 6px; vertical-align: middle; }
    .jobs-tabs { width: 100%; }
    .row-actions { display: flex; align-items: center; gap: 6px; }
    .row-actions button, .row-actions a { font-size: 13px; }
    .release-badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 10px;
      font-weight: 600;
      padding: 1px 8px 1px 5px;
      border-radius: 10px;
      margin-left: 8px;
      background: #37415133;
      color: var(--cg-text-muted);
      letter-spacing: 0.2px;
    }
    .release-badge.upcoming { background: #78350f33; color: #fbbf24; }
    .release-badge app-icon { font-size: 12px; width: 12px; height: 12px; }
    .archive-badge {
      display: inline-flex;
      align-items: center;
      gap: 3px;
      font-size: 10px;
      font-weight: 600;
      padding: 1px 8px 1px 5px;
      border-radius: 10px;
      margin-left: 8px;
      background: #37415133;
      color: var(--cg-text-muted);
      letter-spacing: 0.2px;
    }
    .archive-badge.archived { background: #7f1d1d33; color: #f87171; }
    .archive-badge app-icon { font-size: 12px; width: 12px; height: 12px; }
    .ds-icon-small { width: 32px; height: 32px; display: flex; align-items: center; justify-content: center;
                     border-radius: 6px; background: #37415133; flex-shrink: 0; }
    .ds-icon-small.mysql app-icon { font-size: 18px; color: #f59e0b; }
    .ds-icon-small.postgres app-icon { font-size: 18px; color: #6366f1; }
    .adapter-badge { font-size: 10px; font-weight: 700; padding: 1px 6px; border-radius: 4px;
                     text-transform: uppercase; }
    .adapter-badge.mysql { background: #f59e0b22; color: #f59e0b; }
    .adapter-badge.postgres { background: #6366f122; color: #6366f1; }
    .slug-chip { font-size: 11px; background: var(--cg-surface-2); padding: 1px 6px;
                 border-radius: 4px; color: var(--cg-text-muted); }
  `],
})
export class ProjectTasksComponent implements OnInit {
  tab = 0;
  project?: Project;
  tasks: TaskDefinition[] = [];
  recentExecutions: TaskExecution[] = [];
  dataSources: DataSource[] = [];

  /** Jobs split by archive state — archived ones live in their own tab. */
  get activeTasks(): TaskDefinition[] { return this.tasks.filter(t => !this.archived(t)); }
  get archivedTasks(): TaskDefinition[] { return this.tasks.filter(t => this.archived(t)); }

  isAdmin(): boolean { return this.auth.isAdmin; }

  constructor(
    private api: ApiService,
    private auth: AuthService,
    private route: ActivatedRoute,
    private router: Router,
    private nav: NavContextService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.route.params.subscribe(params => this.load(Number(params['id'])));
  }

  load(id: number): void {
    this.project = undefined;
    forkJoin({
      groups: this.api.listGroups(),
      projects: this.api.listProjects(),
      tasks: this.api.listTasks({ projectId: id }),
      executions: this.api.listExecutions(),
      dataSources: this.api.listProjectDataSources(id).pipe(catchError(() => of([]))),
    }).subscribe(({ groups, projects, tasks, executions, dataSources }) => {
      this.project = projects.find(p => p.id === id);
      this.tasks = tasks;
      const taskIds = new Set(tasks.map(t => t.id));
      this.recentExecutions = executions.filter(e => taskIds.has(e.taskDefinitionId)).slice(0, 10);
      this.dataSources = dataSources;
      this.nav.set(this.buildTrail(groups));
      this.cdr.markForCheck();
    });
  }

  private buildTrail(groups: Group[]): Crumb[] {
    const byId = new Map(groups.map(g => [g.id, g]));
    const chain: Crumb[] = [];
    let gid = this.project?.groupId ?? null;
    const groupChain: Group[] = [];
    let cur = gid != null ? byId.get(gid) : undefined;
    while (cur) {
      groupChain.unshift(cur);
      cur = cur.parentId != null ? byId.get(cur.parentId) : undefined;
    }
    for (const g of groupChain) chain.push({ label: g.name, link: ['/groups', g.id] });
    if (this.project) chain.push({ label: this.project.name });
    return chain;
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

  run(t: TaskDefinition): void {
    if (!this.runnable(t)) return;
    this.api.runTask(t.id).subscribe(res => this.router.navigate(['/executions', res.executionId]));
  }

  remove(t: TaskDefinition): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: t.name, kind: this.i18n.t('common.job') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (ok) this.api.deleteTask(t.id).subscribe(() => {
        this.tasks = this.tasks.filter(x => x.id !== t.id);
        this.cdr.markForCheck();
      });
    });
  }

  duration(e: TaskExecution): string {
    if (!e.startedAt || !e.finishedAt) return '—';
    const ms = new Date(e.finishedAt).getTime() - new Date(e.startedAt).getTime();
    return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
  }
}
