import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { Dialog } from '@angular/cdk/dialog';
import { forkJoin } from 'rxjs';
import { ApiService } from '../services/api.service';
import { AuthService } from '../services/auth.service';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { Group, Project } from '../models';
import { IdentIconComponent } from './ident-icon.component';
import { EntityFormDialogComponent, EntityFormDialogData } from './entity-form-dialog.component';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';

interface GroupRow {
  group: Group;
  projects: Project[];
  subgroups: GroupRow[];
  expanded: boolean;
}

@Component({
  selector: 'app-explore',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink, FormsModule,
    
    IconComponent, TooltipDirective,
    IdentIconComponent, TranslatePipe,
  ],
  template: `
    <div class="explore-wrap">
      <div class="explore-header">
        <div class="explore-title">
          <app-icon>account_tree</app-icon>
          <h1>{{ 'sidebar.explore' | translate }}</h1>
        </div>
        <div class="explore-actions">
          <div class="search-field">
            <app-icon class="search-ic">search</app-icon>
            <input class="cg-input" [placeholder]="'common.search' | translate" [(ngModel)]="filter" (ngModelChange)="applyFilter()">
          </div>
          <button *ngIf="isAdmin" class="cg-btn" (click)="newGroup(null)">
            <app-icon>create_new_folder</app-icon>
            {{ 'sidebar.newGroup' | translate }}
          </button>
        </div>
      </div>

      <div *ngIf="loading" class="loading-center">
        <span class="cg-spinner" style="--d:36px;"></span>
      </div>

      <div *ngIf="loadError" class="empty-state">
        <app-icon style="color:#f87171">error_outline</app-icon>
        <p style="color:#f87171">Failed to load groups. Check the console.</p>
      </div>

      <ng-container *ngIf="!loading && !loadError">
        <div *ngIf="filteredRoots.length === 0" class="empty-state">
          <app-icon>account_tree</app-icon>
          <p>{{ filter ? ('explore.noResults' | translate) : ('sidebar.emptyTree' | translate) }}</p>
        </div>

        <div class="group-list">
          <ng-container *ngFor="let row of pagedRoots">
            <ng-container *ngTemplateOutlet="groupTpl; context: { row: row, depth: 0 }"></ng-container>
          </ng-container>
        </div>

        <div class="cg-pager" *ngIf="totalPages > 1">
          <button class="cg-icon-btn" [disabled]="pageIndex === 0" (click)="goPage(pageIndex - 1)">
            <app-icon>chevron_left</app-icon>
          </button>
          <span class="pager-info">{{ pageIndex + 1 }} / {{ totalPages }}</span>
          <button class="cg-icon-btn" [disabled]="pageIndex >= totalPages - 1" (click)="goPage(pageIndex + 1)">
            <app-icon>chevron_right</app-icon>
          </button>
        </div>
      </ng-container>
    </div>

    <ng-template #groupTpl let-row="row" let-depth="depth">
      <!-- Group header row -->
      <div class="group-row" [style.margin-left.px]="depth * 20">
        <button class="expand-btn" (click)="row.expanded = !row.expanded">
          <app-icon>{{ row.expanded ? 'expand_more' : 'chevron_right' }}</app-icon>
        </button>
        <app-ident-icon [name]="row.group.name" [size]="28"></app-ident-icon>
        <a class="group-name" [routerLink]="['/groups', row.group.id]">{{ row.group.name }}</a>
        <span class="group-meta">
          <span *ngIf="row.subgroups.length">{{ row.subgroups.length }} {{ 'explore.subgroups' | translate }}</span>
          <span *ngIf="row.subgroups.length && row.projects.length" class="sep">·</span>
          <span *ngIf="row.projects.length">{{ row.projects.length }} {{ 'explore.projects' | translate }}</span>
        </span>
        <div class="group-acts" *ngIf="row.group.can?.create || row.group.can?.delete">
          <button *ngIf="row.group.can?.create" class="cg-icon-btn" (click)="newSubgroup(row.group.id)" [cgTooltip]="'sidebar.subgroup' | translate">
            <app-icon>create_new_folder</app-icon>
          </button>
          <button *ngIf="row.group.can?.create" class="cg-icon-btn" (click)="newProject(row.group.id)" [cgTooltip]="'sidebar.newProject' | translate">
            <app-icon>add</app-icon>
          </button>
          <button *ngIf="row.group.can?.delete" class="cg-icon-btn del-btn" (click)="deleteGroup(row.group)" [cgTooltip]="'common.delete' | translate">
            <app-icon>delete</app-icon>
          </button>
        </div>
      </div>

      <!-- Expanded content: subgroups + projects -->
      <ng-container *ngIf="row.expanded">
        <ng-container *ngFor="let sub of row.subgroups">
          <ng-container *ngTemplateOutlet="groupTpl; context: { row: sub, depth: depth + 1 }"></ng-container>
        </ng-container>

        <div *ngIf="row.projects.length > 0" class="projects-grid" [style.padding-left.px]="depth * 20 + 36">
          <a *ngFor="let p of row.projects" class="project-card" [routerLink]="['/projects', p.id]">
            <app-ident-icon [name]="p.name" [size]="24"></app-ident-icon>
            <span class="proj-name">{{ p.name }}</span>
            <app-icon class="proj-arrow">chevron_right</app-icon>
          </a>
        </div>

        <div *ngIf="row.subgroups.length === 0 && row.projects.length === 0"
             class="empty-group" [style.margin-left.px]="depth * 20 + 36">
          {{ 'explore.emptyGroup' | translate }}
        </div>
      </ng-container>
    </ng-template>
  `,
  styles: [`
    .explore-wrap { max-width: 900px; }

    .explore-header {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
      margin-bottom: 24px;
    }
    .explore-title {
      display: flex;
      align-items: center;
      gap: 10px;
      flex: 1;
      app-icon { font-size: 26px; width: 26px; height: 26px; color: var(--cg-accent); }
      h1 { margin: 0; font-size: 22px; font-weight: 700; color: var(--cg-text); }
    }
    .explore-actions {
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .search-field {
      position: relative;
      width: 220px;
      display: flex;
      align-items: center;
    }
    .search-field .search-ic {
      position: absolute; left: 9px;
      font-size: 18px; color: var(--cg-text-muted); pointer-events: none;
    }
    .search-field .cg-input { padding-left: 34px; }

    .cg-pager {
      display: flex; align-items: center; justify-content: center; gap: 12px;
      margin-top: 16px;
    }
    .cg-pager .pager-info { font-size: 13px; color: var(--cg-text-muted); }

    .loading-center {
      display: flex;
      justify-content: center;
      padding: 60px;
    }

    .empty-state {
      text-align: center;
      padding: 60px 20px;
      color: var(--cg-text-muted);
      app-icon { font-size: 48px; width: 48px; height: 48px; opacity: 0.3; }
      p { margin-top: 12px; font-size: 14px; }
    }

    .group-list { display: flex; flex-direction: column; gap: 4px; }

    .group-row {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 10px 12px;
      border-radius: 8px;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      transition: border-color 0.12s;

      &:hover { border-color: var(--cg-accent); }
    }

    .expand-btn {
      background: none;
      border: none;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      color: var(--cg-text-muted);
      padding: 0;
      width: 24px;
      height: 24px;
      flex-shrink: 0;
      border-radius: 4px;
      transition: background 0.12s, color 0.12s;
      &:hover { background: var(--cg-border); color: var(--cg-text); }
      app-icon { font-size: 18px; width: 18px; height: 18px; }
    }

    .group-name {
      font-size: 15px;
      font-weight: 600;
      color: var(--cg-text);
      text-decoration: none;
      &:hover { color: var(--cg-accent); text-decoration: underline; }
    }

    .group-meta {
      flex: 1;
      font-size: 12px;
      color: var(--cg-text-muted);
      display: flex;
      gap: 6px;
      .sep { opacity: 0.4; }
    }

    .group-acts {
      display: flex;
      gap: 0;
      opacity: 0;
      transition: opacity 0.12s;
    }
    .group-row:hover .group-acts { opacity: 1; }
    .del-btn { color: var(--cg-text-muted); &:hover app-icon { color: #f87171; } }

    .projects-grid {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      padding: 8px 0 8px;
    }

    .project-card {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 6px;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      text-decoration: none;
      color: var(--cg-text);
      font-size: 13px;
      font-weight: 500;
      transition: border-color 0.12s, background 0.12s;
      cursor: pointer;

      &:hover {
        border-color: var(--cg-accent);
        background: var(--cg-accent-soft);
      }

      .proj-name { flex: 1; }
      .proj-arrow { font-size: 16px; width: 16px; height: 16px; opacity: 0.4; }
    }

    .empty-group {
      font-size: 12px;
      color: var(--cg-text-muted);
      font-style: italic;
      padding: 8px 0;
    }
  `],
})
export class ExploreComponent implements OnInit {
  loading = true;
  loadError = false;
  filter = '';
  isAdmin = false;

  allRoots: GroupRow[] = [];
  filteredRoots: GroupRow[] = [];
  pagedRoots: GroupRow[] = [];

  pageSize = 10;
  pageIndex = 0;

  get totalPages(): number {
    return Math.max(1, Math.ceil(this.filteredRoots.length / this.pageSize));
  }

  goPage(i: number): void {
    this.pageIndex = Math.min(Math.max(0, i), this.totalPages - 1);
    this.updatePage();
  }

  constructor(
    private api: ApiService,
    public auth: AuthService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.isAdmin = this.auth.isAdmin;
    this.load();
  }

  load(): void {
    this.loading = true;
    forkJoin({ groups: this.api.listGroups(), projects: this.api.listProjects() })
      .subscribe({
        next: ({ groups, projects }) => {
          this.allRoots = this.buildTree(groups, projects);
          this.applyFilter();
          this.loading = false;
          this.cdr.markForCheck();
        },
        error: (err) => { console.error('[Explorer] load error', err); this.loading = false; this.loadError = true; this.cdr.markForCheck(); },
      });
  }

  applyFilter(): void {
    const q = this.filter.trim().toLowerCase();
    this.filteredRoots = q
      ? this.allRoots.filter(r => this.rowMatches(r, q))
      : [...this.allRoots];
    this.pageIndex = 0;
    this.updatePage();
  }

  private updatePage(): void {
    const start = this.pageIndex * this.pageSize;
    this.pagedRoots = this.filteredRoots.slice(start, start + this.pageSize);
  }

  private rowMatches(row: GroupRow, q: string): boolean {
    if (row.group.name.toLowerCase().includes(q)) return true;
    if (row.projects.some(p => p.name.toLowerCase().includes(q))) return true;
    return row.subgroups.some(s => this.rowMatches(s, q));
  }

  private buildTree(groups: Group[], projects: Project[]): GroupRow[] {
    const map = new Map<number, GroupRow>();
    for (const g of groups) {
      map.set(g.id, { group: g, projects: [], subgroups: [], expanded: false });
    }
    for (const p of projects) {
      if (p.groupId != null && map.has(p.groupId)) {
        map.get(p.groupId)!.projects.push(p);
      }
    }
    const roots: GroupRow[] = [];
    for (const g of groups) {
      const row = map.get(g.id)!;
      if (g.parentId != null && map.has(g.parentId)) {
        map.get(g.parentId)!.subgroups.push(row);
      } else {
        roots.push(row);
      }
    }
    return roots;
  }

  newGroup(parentId: number | null): void {
    const data: EntityFormDialogData = {
      titleKey: parentId ? 'groupForm.newSubgroup' : 'sidebar.newGroup',
      namePlaceholderKey: 'groupForm.namePlaceholder',
      descPlaceholderKey: 'groupForm.descPlaceholder',
      createErrorKey: 'groupForm.createError',
      submit: (body) => this.api.createGroup({ ...body, parentId }),
    };
    const ref = this.dialog.open(EntityFormDialogComponent, { data, width: '400px' });
    ref.closed.subscribe(ok => { if (ok) this.load(); });
  }

  newSubgroup(parentId: number): void { this.newGroup(parentId); }

  newProject(groupId: number): void {
    const data: EntityFormDialogData = {
      titleKey: 'projectForm.title',
      namePlaceholderKey: 'projectForm.namePlaceholder',
      descPlaceholderKey: 'projectForm.descPlaceholder',
      createErrorKey: 'projectForm.createError',
      submit: (body) => this.api.createProject({ ...body, groupId }),
    };
    const ref = this.dialog.open(EntityFormDialogComponent, { data, width: '400px' });
    ref.closed.subscribe(ok => { if (ok) this.load(); });
  }

  deleteGroup(group: Group): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: group.name, kind: this.i18n.t('common.group') }, width: '460px',
    });
    ref.closed.subscribe(ok => { if (ok) this.api.deleteGroup(group.id).subscribe(() => this.load()); });
  }
}
