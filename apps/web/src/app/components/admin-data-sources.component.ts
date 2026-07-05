import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Dialog } from '@angular/cdk/dialog';
import { forkJoin } from 'rxjs';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { DataSource, Group, Project } from '../models';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';

interface HealthState {
  [id: number]: { loading: boolean; status?: string; latencyMs?: number; error?: string };
}

@Component({
  selector: 'app-admin-data-sources',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective, TranslatePipe,
  ],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">storage</app-icon>
      <div>
        <h2 class="page-title">{{ 'dataSources.title' | translate }}</h2>
        <p class="page-subtitle">{{ 'dataSources.subtitle' | translate:{ count: sources.length } }}</p>
      </div>
      <button class="cg-btn cg-btn-primary" (click)="openForm()" style="margin-left:auto;">
        <app-icon>add</app-icon> {{ 'dataSources.new' | translate }}
      </button>
    </div>

    <!-- Inline form for create/edit -->
    <div class="cg-panel" *ngIf="formOpen">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">edit</app-icon>
        <p class="cg-panel-title">{{ editing ? ('common.edit' | translate) : ('dataSources.new' | translate) }}</p>
        <button class="cg-icon-btn" (click)="closeForm()" style="margin-left:auto;">
          <app-icon>close</app-icon>
        </button>
      </div>
      <div class="cg-panel-body padded">
        <div class="form-grid">
          <div class="cg-field">
            <label class="cg-label">{{ 'common.name' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.name" (ngModelChange)="onNameChange()">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.slug' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.slug">
            <span class="field-hint">{{ 'dataSources.slugHint' | translate }}</span>
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.adapter' | translate }}</label>
            <div class="select-wrap">
              <select class="cg-select" [(ngModel)]="form.adapter" (ngModelChange)="onAdapterChange()">
                <option value="mysql">MySQL / MariaDB</option>
                <option value="postgres">PostgreSQL</option>
              </select>
              <app-icon class="select-arrow">expand_more</app-icon>
            </div>
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.host' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.host">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.port' | translate }}</label>
            <input class="cg-input" type="number" [(ngModel)]="form.port">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.database' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.database_name">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.username' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.username">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'dataSources.password' | translate }}</label>
            <input class="cg-input" type="password" [(ngModel)]="form.password"
                   [placeholder]="editing ? ('dataSources.passwordHint' | translate) : ''">
          </div>
          <div class="ssl-row">
            <label class="check-row">
              <input type="checkbox" [(ngModel)]="form.ssl" />
              <span>{{ 'dataSources.ssl' | translate }}</span>
            </label>
          </div>
          <div class="cg-field full-width">
            <label class="cg-label">{{ 'dataSources.notes' | translate }}</label>
            <textarea class="cg-textarea" [(ngModel)]="form.notes" rows="2"></textarea>
          </div>
        </div>

        <!-- Project assignment -->
        <div class="section-divider">
          <span class="section-label"><app-icon>folder_open</app-icon>{{ 'dataSources.projects' | translate }}</span>
        </div>
        <div class="project-list">
          <div *ngIf="allProjects.length === 0" class="cg-empty" style="padding:8px 0;">
            {{ 'projects.emptyList' | translate }}
          </div>
          <label *ngFor="let p of allProjects" class="project-check-row">
            <input type="checkbox"
              [checked]="form.projectIds.includes(p.id)"
              (change)="toggleProject(p.id, $any($event.target).checked)" />
            <span class="proj-name">{{ p.name }}</span>
            <span class="proj-group" *ngIf="groupName(p)">{{ groupName(p) }}</span>
          </label>
        </div>
      </div>
      <div class="cg-panel-footer">
        <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="saving">
          <span *ngIf="saving" class="cg-spinner" style="width:14px;height:14px;"></span>
          {{ 'common.save' | translate }}
        </button>
        <button class="cg-btn" (click)="closeForm()">{{ 'common.cancel' | translate }}</button>
      </div>
    </div>

    <!-- List -->
    <div class="cg-panel">
      <div class="cg-panel-body">
        <div *ngIf="sources.length === 0" class="cg-empty">{{ 'dataSources.emptyList' | translate }}</div>
        <div *ngFor="let ds of sources" class="list-row ds-row">
          <div class="ds-icon" [class.mysql]="ds.adapter === 'mysql'" [class.postgres]="ds.adapter === 'postgres'">
            <app-icon>{{ ds.adapter === 'mysql' ? 'table_chart' : 'dns' }}</app-icon>
          </div>
          <div class="row-main">
            <span class="row-title-line">
              <span class="row-title">{{ ds.name }}</span>
              <span class="adapter-badge {{ ds.adapter }}">{{ ds.adapter }}</span>
              <code class="slug-chip">{{ ds.slug }}</code>
            </span>
            <span class="row-desc">
              {{ ds.host }}:{{ ds.port }} / {{ ds.databaseName }}
              <span *ngIf="ds.ssl" class="ssl-badge">
                <app-icon>lock</app-icon>SSL
              </span>
            </span>
            <!-- Project chips -->
            <span class="project-chips" *ngIf="ds.projectIds.length > 0">
              <span class="proj-chip" *ngFor="let pid of ds.projectIds">{{ projectLabel(pid) }}</span>
            </span>
            <span class="row-desc" *ngIf="ds.projectIds.length === 0" style="color:var(--cg-text-muted);font-style:italic;">
              {{ 'dataSources.noProjects' | translate }}
            </span>
            <!-- Health result -->
            <span *ngIf="health[ds.id]" class="health-result"
                  [class.ok]="health[ds.id].status === 'ok'"
                  [class.err]="health[ds.id].status === 'error'">
              <span *ngIf="health[ds.id].loading" class="cg-spinner" style="width:12px;height:12px;"></span>
              <ng-container *ngIf="!health[ds.id].loading">
                <app-icon *ngIf="health[ds.id].status === 'ok'">check_circle</app-icon>
                <app-icon *ngIf="health[ds.id].status === 'error'">error</app-icon>
                {{ health[ds.id].status === 'ok'
                    ? ('dataSources.healthOk' | translate:{ ms: health[ds.id].latencyMs })
                    : ('dataSources.healthError' | translate:{ error: health[ds.id].error }) }}
              </ng-container>
            </span>
          </div>
          <div class="row-actions">
            <button class="cg-btn" (click)="pingHealth(ds)" [cgTooltip]="'dataSources.health' | translate">
              <app-icon>wifi_tethering</app-icon>
            </button>
            <button class="cg-btn" (click)="openForm(ds)" [cgTooltip]="'common.edit' | translate">
              <app-icon>edit</app-icon>
            </button>
            <button class="cg-btn cg-btn-danger" (click)="remove(ds)" [cgTooltip]="'common.delete' | translate">
              <app-icon>delete</app-icon>
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }
    .form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px 16px; }
    .form-grid .full-width { grid-column: 1 / -1; }
    .form-grid .ssl-row { grid-column: 1 / -1; padding: 2px 0; }
    .select-wrap { position: relative; display: flex; align-items: center; }
    .select-wrap .cg-select { flex: 1; padding-right: 28px; }
    .select-arrow { position: absolute; right: 6px; font-size: 16px; pointer-events: none; opacity: .5; }
    .check-row { display: flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
    .check-row input[type="checkbox"] { width: 15px; height: 15px; cursor: pointer; accent-color: var(--cg-accent); }
    .section-divider { display: flex; align-items: center; gap: 8px; margin: 16px 0 10px;
                       border-top: 1px solid var(--cg-border); padding-top: 14px; }
    .section-label { display: flex; align-items: center; gap: 6px; font-size: 13px;
                     font-weight: 600; color: var(--cg-text-muted); }
    .section-label app-icon { font-size: 16px; width: 16px; height: 16px; }
    .project-list { display: flex; flex-direction: column; gap: 2px; max-height: 220px; overflow-y: auto; }
    .project-check-row { display: flex; align-items: center; gap: 10px; padding: 4px 0; cursor: pointer; }
    .project-check-row input[type="checkbox"] { width: 15px; height: 15px; cursor: pointer; accent-color: var(--cg-accent); }
    .proj-name { font-size: 14px; }
    .proj-group { font-size: 11px; color: var(--cg-text-muted); }
    .cg-panel-footer { padding: 12px 16px; display: flex; gap: 8px; border-top: 1px solid var(--cg-border); }
    .padded { padding: 16px; }
    .field-hint { font-size: 11px; color: var(--cg-text-muted); }
    .ds-row { align-items: flex-start; }
    .ds-icon { display: flex; align-items: center; justify-content: center; width: 40px; height: 40px;
               border-radius: 8px; background: #37415133; flex-shrink: 0; }
    .ds-icon.mysql app-icon { color: #f59e0b; }
    .ds-icon.postgres app-icon { color: #6366f1; }
    .adapter-badge { font-size: 10px; font-weight: 700; padding: 1px 6px; border-radius: 4px;
                     text-transform: uppercase; letter-spacing: 0.5px; }
    .adapter-badge.mysql { background: #f59e0b22; color: #f59e0b; }
    .adapter-badge.postgres { background: #6366f122; color: #6366f1; }
    .slug-chip { font-size: 11px; background: var(--cg-surface-2); padding: 1px 6px; border-radius: 4px;
                 color: var(--cg-text-muted); }
    .row-title-line { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .ssl-badge { display: inline-flex; align-items: center; gap: 2px; font-size: 10px;
                 color: #4ade80; margin-left: 4px; }
    .ssl-badge app-icon { font-size: 12px; width: 12px; height: 12px; }
    .project-chips { display: flex; gap: 4px; flex-wrap: wrap; margin-top: 2px; }
    .proj-chip { font-size: 11px; padding: 1px 8px; border-radius: 10px;
                 background: var(--cg-surface-2); color: var(--cg-text-muted); }
    .health-result { display: inline-flex; align-items: center; gap: 4px; font-size: 11px; margin-top: 2px; }
    .health-result.ok { color: #4ade80; }
    .health-result.err { color: #f87171; }
    .health-result app-icon { font-size: 14px; width: 14px; height: 14px; }
    .row-actions { display: flex; gap: 6px; align-items: center; flex-shrink: 0; }
  `],
})
export class AdminDataSourcesComponent implements OnInit {
  sources: DataSource[] = [];
  allProjects: Project[] = [];
  projectMap = new Map<number, Project>();
  groupMap = new Map<number, Group>();
  health: HealthState = {};
  formOpen = false;
  editing: DataSource | null = null;
  saving = false;

  form: {
    name: string; slug: string; adapter: 'mysql' | 'postgres';
    host: string; port: number; database_name: string;
    username: string; password: string; ssl: boolean; notes: string;
    projectIds: number[];
  } = this.emptyForm();

  constructor(
    private api: ApiService,
    private nav: NavContextService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('dataSources.title') }]);
    this.reload();
  }

  reload(): void {
    forkJoin({
      sources:  this.api.listDataSources(),
      projects: this.api.listProjects(),
      groups:   this.api.listGroups(),
    }).subscribe(({ sources, projects, groups }) => {
      this.sources     = sources;
      this.allProjects = projects;
      this.projectMap  = new Map(projects.map(p => [p.id, p]));
      this.groupMap    = new Map(groups.map(g => [g.id, g]));
      this.cdr.markForCheck();
    });
  }

  openForm(ds?: DataSource): void {
    this.editing = ds ?? null;
    if (ds) {
      this.form = {
        name: ds.name, slug: ds.slug, adapter: ds.adapter,
        host: ds.host, port: ds.port, database_name: ds.databaseName,
        username: ds.username, password: '', ssl: ds.ssl, notes: ds.notes ?? '',
        projectIds: [...ds.projectIds],
      };
    } else {
      this.form = this.emptyForm();
    }
    this.formOpen = true;
  }

  closeForm(): void { this.formOpen = false; this.editing = null; }

  toggleProject(id: number, checked: boolean): void {
    if (checked) {
      if (!this.form.projectIds.includes(id)) this.form.projectIds = [...this.form.projectIds, id];
    } else {
      this.form.projectIds = this.form.projectIds.filter(x => x !== id);
    }
  }

  onNameChange(): void {
    if (!this.editing) {
      this.form.slug = this.form.name
        .toLowerCase()
        .normalize('NFD').replace(/[̀-ͯ]/g, '')
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '')
        .slice(0, 50);
    }
  }

  onAdapterChange(): void {
    this.form.port = this.form.adapter === 'mysql' ? 3306 : 5432;
  }

  save(): void {
    this.saving = true;
    const { projectIds, ...dsAttrs } = this.form;
    const attrs: Record<string, unknown> = { ...dsAttrs };
    if (!attrs['password']) delete attrs['password'];

    const prevIds = this.editing?.projectIds ?? [];
    const toAdd    = projectIds.filter(id => !prevIds.includes(id));
    const toRemove = prevIds.filter(id => !projectIds.includes(id));

    const saveObs = this.editing
      ? this.api.updateDataSource(this.editing.id, attrs as Partial<DataSource> & { password?: string })
      : this.api.createDataSource(attrs as Partial<DataSource> & { password?: string });

    saveObs.subscribe({
      next: (saved) => {
        const dsId = saved.id;
        const assigns = [
          ...toAdd.map(pid    => this.api.assignDataSourceToProject(pid, dsId)),
          ...toRemove.map(pid => this.api.unassignDataSourceFromProject(pid, dsId)),
        ];
        if (assigns.length === 0) {
          this.saving = false; this.closeForm(); this.reload();
          this.cdr.markForCheck();
        } else {
          forkJoin(assigns).subscribe({
            next:  () => { this.saving = false; this.closeForm(); this.reload(); this.cdr.markForCheck(); },
            error: () => { this.saving = false; this.closeForm(); this.reload(); this.cdr.markForCheck(); },
          });
        }
      },
      error: () => { this.saving = false; this.cdr.markForCheck(); },
    });
  }

  pingHealth(ds: DataSource): void {
    this.health[ds.id] = { loading: true };
    this.api.checkDataSourceHealth(ds.id).subscribe({
      next:  res => { this.health[ds.id] = { loading: false, ...res }; this.cdr.markForCheck(); },
      error: ()  => { this.health[ds.id] = { loading: false, status: 'error', error: 'request failed' }; this.cdr.markForCheck(); },
    });
  }

  remove(ds: DataSource): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: ds.name, kind: this.i18n.t('dataSources.title') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (ok) this.api.deleteDataSource(ds.id).subscribe(() => this.reload());
    });
  }

  projectLabel(id: number): string {
    return this.projectMap.get(id)?.name ?? `#${id}`;
  }

  groupName(p: Project): string {
    return p.groupId != null ? (this.groupMap.get(p.groupId)?.name ?? '') : '';
  }

  private emptyForm() {
    return {
      name: '', slug: '', adapter: 'mysql' as const, host: 'localhost', port: 3306,
      database_name: '', username: '', password: '', ssl: false, notes: '', projectIds: [] as number[],
    };
  }
}
