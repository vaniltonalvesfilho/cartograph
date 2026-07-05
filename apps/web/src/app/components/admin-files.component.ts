import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, OnInit, ViewChild } from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { Dialog } from '@angular/cdk/dialog';
import { ApiService } from '../services/api.service';
import { AuthService } from '../services/auth.service';
import { NavContextService } from '../services/nav-context.service';
import { FileEntry } from '../models';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { extractApiError } from '../utils/http-error.util';

/**
 * File manager over the job data sandbox: browse folders, upload, download
 * and delete the files that DSL steps (readDirectory, writeOutput, parseJson,
 * …) consume and produce.
 *
 * Admins see the whole `data/` tree. Members see one virtual folder per
 * project they can view (`projects/<id>` under the hood — the same dir their
 * project's jobs are confined to); upload/delete need the project's :edit.
 */
@Component({
  selector: 'app-admin-files',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, DatePipe, IconComponent, TooltipDirective, TranslatePipe],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">folder</app-icon>
      <div>
        <h2 class="page-title">{{ 'files.title' | translate }}</h2>
        <p class="page-subtitle">{{ (isAdmin ? 'files.subtitle' : 'files.subtitleMember') | translate }}</p>
      </div>
      <button *ngIf="canWrite" class="cg-btn" style="margin-left:auto;" (click)="startFolder()">
        <app-icon>create_new_folder</app-icon>
        {{ 'files.newFolder' | translate }}
      </button>
      <label *ngIf="canWrite" class="cg-btn cg-btn-primary" [class.disabled]="uploading">
        <app-icon>upload</app-icon>
        {{ (uploading ? 'files.uploading' : 'files.upload') | translate }}
        <input type="file" hidden (change)="onFilePicked($event)" [disabled]="uploading" />
      </label>
      <span *ngIf="!canWrite && path" class="ro-badge" style="margin-left:auto;">
        <app-icon style="font-size:14px;">lock</app-icon> {{ 'files.readOnly' | translate }}
      </span>
    </div>

    <div class="cg-panel">
      <div class="cg-panel-header">
        <!-- Path breadcrumb: root + one chip per folder entered -->
        <nav class="crumbs">
          <button class="crumb" (click)="goTo(-1)" [class.current]="crumbs.length === 0">
            <app-icon style="font-size:16px;">home</app-icon> {{ isAdmin ? 'data' : ('files.title' | translate) }}
          </button>
          <ng-container *ngFor="let c of crumbs; let i = index">
            <span class="crumb-sep">/</span>
            <button class="crumb" (click)="goTo(i)" [class.current]="i === crumbs.length - 1">{{ c.label }}</button>
          </ng-container>
        </nav>
      </div>

      <p *ngIf="error" style="color:#e5484d;font-size:13px;margin:10px 18px 0;">{{ error }}</p>

      <div class="cg-panel-body">
        <div *ngIf="creatingFolder" class="new-folder-row">
          <app-icon style="color:var(--cg-accent);">create_new_folder</app-icon>
          <input #folderName class="cg-input" style="flex:1;max-width:320px;"
                 [placeholder]="'files.folderName' | translate"
                 (keydown.enter)="createFolder(folderName.value)"
                 (keydown.escape)="cancelFolder()" />
          <button class="cg-btn cg-btn-primary" (click)="createFolder(folderName.value)">
            {{ 'files.create' | translate }}
          </button>
          <button class="cg-btn" (click)="cancelFolder()">{{ 'common.cancel' | translate }}</button>
        </div>

        <div *ngIf="loading" style="display:flex;justify-content:center;padding:28px;"><span class="cg-spinner"></span></div>

        <ng-container *ngIf="!loading">
          <div *ngFor="let e of entries" class="list-row">
            <app-icon [style.color]="e.isDir ? 'var(--cg-accent)' : 'var(--cg-text-muted)'">
              {{ e.isDir ? 'folder' : 'description' }}
            </app-icon>
            <div class="row-main">
              <a *ngIf="e.isDir" class="row-title" style="cursor:pointer;" (click)="enter(e)">{{ e.name }}</a>
              <span *ngIf="!e.isDir" class="row-title">{{ e.name }}</span>
              <span *ngIf="!e.path" class="row-desc mono-path">{{ stepHint(e) }}</span>
            </div>
            <span class="row-meta" *ngIf="!e.isDir">{{ formatSize(e.size) }}</span>
            <span class="row-meta" *ngIf="e.modifiedAt">{{ e.modifiedAt | date:'dd/MM/yy HH:mm' }}</span>
            <button *ngIf="!e.isDir" class="cg-icon-btn" (click)="download(e)"
                    [cgTooltip]="'files.download' | translate"><app-icon>download</app-icon></button>
            <button *ngIf="canWrite" class="cg-icon-btn" (click)="remove(e)"
                    [cgTooltip]="'files.delete' | translate"><app-icon>delete</app-icon></button>
          </div>

          <div *ngIf="entries.length === 0" style="padding:24px 18px;color:var(--cg-text-muted);font-size:13.5px;">
            {{ 'files.empty' | translate }}
          </div>
        </ng-container>
      </div>
    </div>
  `,
  styles: [`
    .crumbs { display: flex; align-items: center; gap: 2px; flex-wrap: wrap; }
    .crumb {
      display: inline-flex; align-items: center; gap: 4px;
      border: none; background: transparent; cursor: pointer;
      color: var(--cg-text-muted); font-size: 13.5px; font-weight: 600;
      padding: 3px 6px; border-radius: 6px;
    }
    .crumb:hover { background: var(--cg-surface-2); color: var(--cg-text); }
    .crumb.current { color: var(--cg-text); }
    .crumb-sep { color: var(--cg-text-muted); opacity: .6; }
    .mono-path { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    label.cg-btn input { display: none; }
    label.cg-btn.disabled { opacity: .6; pointer-events: none; }
    .ro-badge {
      display: inline-flex; align-items: center; gap: 4px;
      font-size: 12px; color: var(--cg-text-muted);
      border: 1px solid var(--cg-border); border-radius: 999px;
      padding: 3px 10px;
    }
    .new-folder-row {
      display: flex; align-items: center; gap: 8px;
      padding: 10px 18px; border-bottom: 1px solid var(--cg-border);
    }
  `],
})
export class AdminFilesComponent implements OnInit {
  path = '';
  /** Breadcrumb of entered folders; labels may differ from path segments
   *  (a member's project folder is displayed by project name). */
  crumbs: { label: string; path: string }[] = [];
  entries: FileEntry[] = [];
  canWrite = false;
  loading = true;
  uploading = false;
  creatingFolder = false;
  error = '';

  @ViewChild('folderName') folderNameInput?: ElementRef<HTMLInputElement>;

  constructor(
    private api: ApiService,
    private auth: AuthService,
    private nav: NavContextService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  get isAdmin(): boolean {
    return this.auth.isAdmin;
  }

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('files.title') }]);
    this.load();
  }

  private load(): void {
    this.loading = true;
    this.error = '';
    this.api.listFiles(this.path).subscribe({
      next: (res) => {
        this.entries = res.entries;
        this.canWrite = res.canWrite;
        this.loading = false;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.entries = [];
        this.canWrite = false;
        this.loading = false;
        this.error = extractApiError(err, this.i18n.t('files.loadError'));
        this.cdr.markForCheck();
      },
    });
  }

  enter(entry: FileEntry): void {
    this.path = entry.path ?? (this.path ? `${this.path}/${entry.name}` : entry.name);
    this.crumbs = [...this.crumbs, { label: entry.name, path: this.path }];
    this.load();
  }

  /** -1 = root; otherwise index of the last kept crumb. */
  goTo(index: number): void {
    this.crumbs = this.crumbs.slice(0, index + 1);
    this.path = this.crumbs[this.crumbs.length - 1]?.path ?? '';
    this.load();
  }

  /** Path to paste into a step param: relative to the sandbox the job will
   *  run in (its project folder for project jobs, `data/` otherwise). */
  stepHint(entry: FileEntry): string {
    const full = this.path ? `${this.path}/${entry.name}` : entry.name;
    return 'data/' + full.replace(/^projects\/\d+\/?/, '');
  }

  startFolder(): void {
    this.creatingFolder = true;
    setTimeout(() => this.folderNameInput?.nativeElement.focus());
  }

  cancelFolder(): void {
    this.creatingFolder = false;
  }

  createFolder(name: string): void {
    name = name.trim();
    if (!name) return;

    this.error = '';
    this.api.createFolder(this.path, name).subscribe({
      next: () => {
        this.creatingFolder = false;
        this.load();
      },
      error: (err) => {
        this.error = extractApiError(err, this.i18n.t('files.mkdirError'));
        this.cdr.markForCheck();
      },
    });
  }

  onFilePicked(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;

    this.uploading = true;
    this.error = '';
    this.api.uploadFile(this.path, file).subscribe({
      next: () => {
        this.uploading = false;
        this.load();
      },
      error: (err) => {
        this.uploading = false;
        this.error = extractApiError(err, this.i18n.t('files.uploadError'));
        this.cdr.markForCheck();
      },
    });
  }

  download(entry: FileEntry): void {
    const rel = this.path ? `${this.path}/${entry.name}` : entry.name;
    this.api.downloadFile(rel).subscribe({
      next: (blob) => {
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = entry.name;
        a.click();
        URL.revokeObjectURL(url);
      },
      error: (err) => {
        this.error = extractApiError(err, this.i18n.t('files.loadError'));
        this.cdr.markForCheck();
      },
    });
  }

  remove(entry: FileEntry): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: entry.name, kind: this.i18n.t(entry.isDir ? 'files.kindFolder' : 'files.kindFile') },
      width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (!ok) return;
      const rel = this.path ? `${this.path}/${entry.name}` : entry.name;
      this.api.deleteFile(rel).subscribe({
        next: () => this.load(),
        error: (err) => {
          this.error = extractApiError(err, this.i18n.t('files.deleteError'));
          this.cdr.markForCheck();
        },
      });
    });
  }

  formatSize(bytes: number | null): string {
    if (bytes == null) return '';
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
}
