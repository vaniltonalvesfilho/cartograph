import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { Router, RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { Dialog } from '@angular/cdk/dialog';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { TaskDefinition } from '../models';
import { IdentIconComponent } from './ident-icon.component';
import { JobGraphComponent } from './job-graph.component';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { CopyIdComponent } from './copy-id.component';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-task-list',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink, DatePipe,
    IconComponent, TooltipDirective,
    IdentIconComponent, JobGraphComponent, CopyIdComponent, TranslatePipe,
  ],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">grid_view</app-icon>
      <div>
        <h2 class="page-title">{{ 'sidebar.allJobs' | translate }}</h2>
        <p class="page-subtitle">{{ 'tasks.subtitle' | translate:{ count: tasks.length } }}</p>
      </div>
      <a routerLink="/tasks/new" class="cg-btn cg-btn-primary" style="margin-left: auto;">
        <app-icon>add</app-icon> {{ 'tasks.new' | translate }}
      </a>
    </div>

    <!-- Dependency graph -->
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">account_tree</app-icon>
        <p class="cg-panel-title">{{ 'tasks.depGraph' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;" [innerHTML]="'tasks.depGraphHint' | translate"></p>
      </div>
      <app-job-graph [tasks]="tasks"></app-job-graph>
    </div>

    <!-- Lista de jobs (ativos / arquivados) -->
    <div class="cg-panel">
      <div class="cg-tabs">
        <button class="cg-tab" [class.active]="tab === 0" (click)="tab = 0">
          <app-icon class="tab-icon">list</app-icon>{{ 'tasks.activeTab' | translate }} ({{ activeTasks.length }})
        </button>
        <button class="cg-tab" [class.active]="tab === 1" (click)="tab = 1">
          <app-icon class="tab-icon">inventory_2</app-icon>{{ 'tasks.archivedTab' | translate }} ({{ archivedTasks.length }})
        </button>
      </div>
      <div class="cg-panel-body" *ngIf="tab === 0">
        <ng-container *ngTemplateOutlet="jobList; context: { list: activeTasks, emptyKey: 'tasks.emptyList' }"></ng-container>
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
            <span *ngIf="!t.cron">{{ 'tasks.manualCreatedPrefix' | translate }} {{ t.createdAt | date:'dd/MM/yy' }}</span>
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
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }
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
  `],
})
export class TaskListComponent implements OnInit {
  tasks: TaskDefinition[] = [];
  tab = 0;

  /** Jobs split by archive state — archived ones live in their own tab. */
  get activeTasks(): TaskDefinition[] { return this.tasks.filter(t => !this.archived(t)); }
  get archivedTasks(): TaskDefinition[] { return this.tasks.filter(t => this.archived(t)); }

  constructor(
    private api: ApiService,
    private router: Router,
    private nav: NavContextService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('sidebar.allJobs') }]);
    this.reload();
  }

  reload(): void {
    this.api.listTasks().subscribe(t => {
      this.tasks = t;
      this.cdr.markForCheck();
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

  run(t: TaskDefinition): void {
    if (!this.runnable(t)) return;
    this.api.runTask(t.id).subscribe(res => this.router.navigate(['/executions', res.executionId]));
  }

  remove(t: TaskDefinition): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: t.name, kind: this.i18n.t('common.job') }, width: '460px',
    });
    ref.closed.subscribe(ok => { if (ok) this.api.deleteTask(t.id).subscribe(() => this.reload()); });
  }
}
