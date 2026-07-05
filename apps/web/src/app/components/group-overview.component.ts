import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { Dialog } from '@angular/cdk/dialog';
import { forkJoin } from 'rxjs';
import { ApiService } from '../services/api.service';
import { NavContextService, Crumb } from '../services/nav-context.service';
import { Group, Project } from '../models';
import { MetricCardComponent } from './metric-card.component';
import { IdentIconComponent } from './ident-icon.component';
import { EntityFormDialogComponent, EntityFormDialogData } from './entity-form-dialog.component';
import { MembersPanelComponent } from './members-panel.component';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-group-overview',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink,
    IconComponent,
    MetricCardComponent, IdentIconComponent, MembersPanelComponent, TranslatePipe,
  ],
  template: `
    <div *ngIf="group" class="page-header">
      <app-ident-icon [name]="group.name" [size]="48"></app-ident-icon>
      <div>
        <h2 class="page-title">{{ group.name }}</h2>
        <p class="page-subtitle">{{ (isSubgroup ? 'groupOverview.subgroup' : 'groupOverview.group') | translate }} · {{ 'groupOverview.counts' | translate:{ projects: projects.length, subgroups: childGroups.length } }}</p>
        <p *ngIf="group.description" class="page-description">{{ group.description }}</p>
      </div>
    </div>

    <div class="metrics-grid" *ngIf="group">
      <app-metric-card [label]="'groupOverview.projectsTitle' | translate" [value]="projects.length"   icon="work_outline"></app-metric-card>
      <app-metric-card [label]="'groupOverview.jobsInGroup' | translate"   [value]="totalJobs"         icon="grid_view"></app-metric-card>
      <app-metric-card [label]="'groupOverview.subgroups' | translate"     [value]="childGroups.length" icon="folder"></app-metric-card>
      <app-metric-card [label]="'dashboard.scheduled' | translate"         [value]="scheduledJobs"     icon="schedule" color="#eab308"></app-metric-card>
    </div>

    <!-- Subgrupos -->
    <div class="cg-panel" *ngIf="childGroups.length > 0">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">folder</app-icon>
        <p class="cg-panel-title">{{ 'groupOverview.subgroups' | translate }}</p>
        <span class="spacer"></span>
        <button *ngIf="group?.can?.create" class="cg-btn" (click)="newSubgroup()">
          <app-icon>create_new_folder</app-icon> {{ 'sidebar.subgroup' | translate }}
        </button>
      </div>
      <div class="cg-panel-body">
        <a *ngFor="let g of childGroups" [routerLink]="['/groups', g.id]" class="list-row">
          <app-ident-icon [name]="g.name" [size]="32"></app-ident-icon>
          <div class="row-main">
            <span class="row-title">{{ g.name }}</span>
            <span class="row-desc">{{ g.description || ('groupOverview.subgroup' | translate) }}</span>
          </div>
          <app-icon class="row-arrow">chevron_right</app-icon>
        </a>
      </div>
    </div>

    <!-- Projetos -->
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">work_outline</app-icon>
        <p class="cg-panel-title">{{ 'groupOverview.projectsTitle' | translate }}</p>
        <span class="spacer"></span>
        <button *ngIf="group?.can?.create" class="cg-btn cg-btn-primary" (click)="newProject()">
          <app-icon>add</app-icon> {{ 'sidebar.newProject' | translate }}
        </button>
      </div>
      <div class="cg-panel-body">
        <div *ngIf="projects.length === 0" class="cg-empty">
          {{ 'groupOverview.emptyProjects' | translate }}
        </div>
        <a *ngFor="let p of projects" [routerLink]="['/projects', p.id]" class="list-row">
          <app-ident-icon [name]="p.name" [size]="32"></app-ident-icon>
          <div class="row-main">
            <span class="row-title">{{ p.name }}</span>
            <span class="row-desc">{{ 'groupOverview.jobCount' | translate:{ count: jobCountByProject.get(p.id) ?? 0 } }}</span>
          </div>
          <app-icon class="row-arrow">chevron_right</app-icon>
        </a>
      </div>
    </div>

    <!-- Membros -->
    <app-members-panel *ngIf="group" subjectType="group" [subjectId]="group.id"></app-members-panel>
  `,
  styles: [`
    .spacer { flex: 1 1 auto; }
    .cg-panel-header button { font-size: 13px; }
  `],
})
export class GroupOverviewComponent implements OnInit {
  group?: Group;
  isSubgroup = false;
  projects: Project[] = [];
  childGroups: Group[] = [];
  jobCountByProject = new Map<number, number>();
  totalJobs = 0;
  scheduledJobs = 0;

  private allGroups: Group[] = [];

  constructor(
    private api: ApiService,
    private route: ActivatedRoute,
    private nav: NavContextService,
    private dialog: Dialog,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.route.params.subscribe(params => this.load(Number(params['id'])));
  }

  load(id: number): void {
    this.group = undefined;
    forkJoin({
      groups: this.api.listGroups(),
      projects: this.api.listProjects(),
      allTasks: this.api.listTasks(),
    }).subscribe(({ groups, projects, allTasks }) => {
      this.allGroups = groups;
      this.group = groups.find(g => g.id === id);
      this.isSubgroup = this.group?.parentId != null;
      this.childGroups = groups.filter(g => g.parentId === id);
      this.projects = projects.filter(p => p.groupId === id);

      const projectIds = new Set(this.projects.map(p => p.id));
      this.jobCountByProject = new Map();
      let total = 0, scheduled = 0;
      for (const task of allTasks) {
        if (task.projectId != null && projectIds.has(task.projectId)) {
          this.jobCountByProject.set(task.projectId, (this.jobCountByProject.get(task.projectId) ?? 0) + 1);
          total++;
          if (task.cron) scheduled++;
        }
      }
      this.totalJobs = total;
      this.scheduledJobs = scheduled;

      this.nav.set(this.buildTrail(id));
      this.cdr.markForCheck();
    });
  }

  private buildTrail(id: number): Crumb[] {
    const byId = new Map(this.allGroups.map(g => [g.id, g]));
    const chain: Group[] = [];
    let cur = byId.get(id);
    while (cur) {
      chain.unshift(cur);
      cur = cur.parentId != null ? byId.get(cur.parentId) : undefined;
    }
    return chain.map((g, i) => i === chain.length - 1
      ? { label: g.name }
      : { label: g.name, link: ['/groups', g.id] });
  }

  newSubgroup(): void {
    if (!this.group) return;
    const parentId = this.group.id;
    const data: EntityFormDialogData = {
      titleKey: 'groupForm.newSubgroup',
      namePlaceholderKey: 'groupForm.namePlaceholder',
      descPlaceholderKey: 'groupForm.descPlaceholder',
      createErrorKey: 'groupForm.createError',
      submit: (body) => this.api.createGroup({ ...body, parentId }),
    };
    const ref = this.dialog.open(EntityFormDialogComponent, { data, width: '400px' });
    ref.closed.subscribe(r => { if (r) this.load(this.group!.id); });
  }

  newProject(): void {
    if (!this.group) return;
    const groupId = this.group.id;
    const data: EntityFormDialogData = {
      titleKey: 'projectForm.title',
      namePlaceholderKey: 'projectForm.namePlaceholder',
      descPlaceholderKey: 'projectForm.descPlaceholder',
      createErrorKey: 'projectForm.createError',
      submit: (body) => this.api.createProject({ ...body, groupId }),
    };
    const ref = this.dialog.open(EntityFormDialogComponent, { data, width: '400px' });
    ref.closed.subscribe(r => { if (r) this.load(this.group!.id); });
  }
}
