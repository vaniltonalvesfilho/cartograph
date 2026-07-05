import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Dialog } from '@angular/cdk/dialog';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { User } from '../models';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { IdentIconComponent } from './ident-icon.component';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

@Component({
  selector: 'app-user-management',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective,
    IdentIconComponent, TranslatePipe,
  ],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">manage_accounts</app-icon>
      <div>
        <h2 class="page-title">{{ 'userMgmt.title' | translate }}</h2>
        <p class="page-subtitle">{{ 'userMgmt.subtitle' | translate:{ count: users.length } }}</p>
      </div>
      <button class="cg-btn cg-btn-primary" style="margin-left:auto;" (click)="openForm()">
        <app-icon>person_add</app-icon> {{ 'userMgmt.newUser' | translate }}
      </button>
    </div>

    <!-- Inline create/edit form -->
    <div class="cg-panel" *ngIf="showForm">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">{{ editId ? 'edit' : 'person_add' }}</app-icon>
        <p class="cg-panel-title">{{ (editId ? 'userMgmt.editUser' : 'userMgmt.newUser') | translate }}</p>
      </div>
      <div class="form-body">
        <div class="cg-field">
          <label class="cg-label">{{ 'common.name' | translate }}</label>
          <input class="cg-input" [(ngModel)]="form.name" [placeholder]="'userMgmt.namePlaceholder' | translate" />
        </div>
        <div class="cg-field">
          <label class="cg-label">{{ 'login.email' | translate }}</label>
          <input class="cg-input" type="email" [(ngModel)]="form.email" placeholder="email@exemplo.com" />
        </div>
        <div class="cg-field">
          <label class="cg-label">{{ (editId ? 'userMgmt.newPassword' : 'login.password') | translate }}</label>
          <div class="pwd-wrap">
            <input class="cg-input" [type]="showPwd ? 'text' : 'password'" [(ngModel)]="form.password" />
            <button class="cg-icon-btn pwd-eye" type="button" tabindex="-1" (click)="showPwd = !showPwd">
              <app-icon>{{ showPwd ? 'visibility_off' : 'visibility' }}</app-icon>
            </button>
          </div>
        </div>
        <label class="check-row">
          <input type="checkbox" [(ngModel)]="form.isAdmin" />
          <span>{{ 'userMgmt.cartographerAdmin' | translate }}</span>
        </label>
        <div class="form-actions">
          <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="saving">
            {{ (saving ? 'common.saving' : 'common.save') | translate }}
          </button>
          <button class="cg-btn" (click)="cancelForm()">{{ 'common.cancel' | translate }}</button>
          <span *ngIf="formError" style="color:#f87171;font-size:13px;">{{ formError }}</span>
        </div>
      </div>
    </div>

    <!-- Users list -->
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">group</app-icon>
        <p class="cg-panel-title">{{ 'sidebar.users' | translate }}</p>
      </div>
      <div class="cg-panel-body">
        <div *ngIf="users.length === 0" class="cg-empty">{{ 'userMgmt.emptyUsers' | translate }}</div>
        <div *ngFor="let u of users" class="list-row" style="cursor:default;">
          <app-ident-icon [name]="u.name" [size]="36"></app-ident-icon>
          <div class="row-main">
            <span class="row-title">
              {{ u.name }}
              <span *ngIf="u.isAdmin" class="admin-badge">Cartographer</span>
            </span>
            <span class="row-desc">{{ u.email }}</span>
          </div>
          <div class="row-actions">
            <button class="cg-btn" (click)="openForm(u)" [cgTooltip]="'common.edit' | translate">
              <app-icon>edit</app-icon>
            </button>
            <button class="cg-btn cg-btn-danger" (click)="deleteUser(u)" [cgTooltip]="'common.delete' | translate">
              <app-icon>delete</app-icon>
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }
    .form-body {
      display: flex;
      flex-direction: column;
      gap: 12px;
      padding: 16px 20px 20px;
    }
    .pwd-wrap { position: relative; display: flex; align-items: center; }
    .pwd-wrap .cg-input { padding-right: 36px; width: 100%; }
    .pwd-eye { position: absolute; right: 4px; }
    .check-row { display: flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
    .check-row input[type="checkbox"] { width: 15px; height: 15px; cursor: pointer; accent-color: var(--cg-accent); }
    .form-actions {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-top: 4px;
    }
    .row-actions { display: flex; gap: 6px; }
    .admin-badge {
      font-size: 10px;
      font-weight: 700;
      padding: 1px 8px;
      border-radius: 10px;
      background: #7f1d1d33;
      color: #f87171;
      margin-left: 6px;
      letter-spacing: 0.3px;
    }
  `],
})
export class UserManagementComponent implements OnInit {
  users: User[] = [];
  showForm = false;
  editId: number | null = null;
  showPwd = false;
  saving = false;
  formError = '';
  form: { name: string; email: string; password: string; isAdmin: boolean } = {
    name: '', email: '', password: '', isAdmin: false,
  };

  constructor(
    private api: ApiService,
    private nav: NavContextService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('sidebar.users') }]);
    this.load();
  }

  load(): void {
    this.api.listUsers().subscribe(u => { this.users = u; this.cdr.markForCheck(); });
  }

  openForm(user?: User): void {
    this.formError = '';
    this.showPwd = false;
    if (user) {
      this.editId = user.id;
      this.form = { name: user.name, email: user.email, password: '', isAdmin: user.isAdmin };
    } else {
      this.editId = null;
      this.form = { name: '', email: '', password: '', isAdmin: false };
    }
    this.showForm = true;
  }

  cancelForm(): void {
    this.showForm = false;
    this.editId = null;
    this.formError = '';
  }

  save(): void {
    this.formError = '';
    if (!this.form.name || !this.form.email) {
      this.formError = this.i18n.t('userMgmt.nameEmailRequired');
      return;
    }
    if (!this.editId && !this.form.password) {
      this.formError = this.i18n.t('userMgmt.passwordRequired');
      return;
    }
    this.saving = true;
    if (this.editId) {
      const body: Record<string, unknown> = { name: this.form.name, email: this.form.email, isAdmin: this.form.isAdmin };
      if (this.form.password) body['password'] = this.form.password;
      this.api.updateUser(this.editId, body as Parameters<ApiService['updateUser']>[1]).subscribe({
        next: () => { this.saving = false; this.cancelForm(); this.load(); this.cdr.markForCheck(); },
        error: () => { this.saving = false; this.formError = this.i18n.t('userMgmt.saveError'); this.cdr.markForCheck(); },
      });
    } else {
      this.api.createUser(this.form).subscribe({
        next: () => { this.saving = false; this.cancelForm(); this.load(); this.cdr.markForCheck(); },
        error: () => { this.saving = false; this.formError = this.i18n.t('userMgmt.createError'); this.cdr.markForCheck(); },
      });
    }
  }

  deleteUser(u: User): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: u.name, kind: this.i18n.t('common.user') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (ok) this.api.deleteUser(u.id).subscribe(() => this.load());
    });
  }
}
