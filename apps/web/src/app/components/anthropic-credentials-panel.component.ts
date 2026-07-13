import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Dialog } from '@angular/cdk/dialog';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { CopyIdComponent } from './copy-id.component';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { ApiService } from '../services/api.service';
import { AnthropicCredential } from '../models';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

/**
 * Anthropic API credentials registered on a project. Any viewer sees name +
 * code (the DSL needs the code for `step "agent"`); creating, editing and
 * deleting require Navigator+ (`can.manageSecrets`). The API key is
 * write-only: it is sent on save and never displayed back.
 */
@Component({
  selector: 'app-anthropic-credentials-panel',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective, CopyIdComponent, TranslatePipe,
  ],
  template: `
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">auto_awesome</app-icon>
        <p class="cg-panel-title">{{ 'anthropicCredentials.title' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'anthropicCredentials.hint' | translate }}</p>
        <span class="spacer"></span>
        <button *ngIf="canManage" class="cg-btn" (click)="startCreate()" style="font-size:13px;">
          <app-icon>add</app-icon> {{ 'anthropicCredentials.add' | translate }}
        </button>
      </div>

      <!-- Create / edit form -->
      <div *ngIf="formOpen && canManage" class="add-form">
        <div class="cg-field" style="width:220px;">
          <label class="cg-label">{{ 'anthropicCredentials.name' | translate }}</label>
          <input class="cg-input" [(ngModel)]="formName" [placeholder]="'anthropicCredentials.namePlaceholder' | translate" />
        </div>
        <div class="cg-field" style="flex:1;min-width:260px;">
          <label class="cg-label">{{ 'anthropicCredentials.key' | translate }}</label>
          <input class="cg-input" type="password" autocomplete="off" [(ngModel)]="formKey"
                 [placeholder]="editing ? ('anthropicCredentials.keyKeep' | translate) : 'sk-ant-…'" />
        </div>
        <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="!formName || (!editing && !formKey)">
          {{ 'common.save' | translate }}
        </button>
        <button class="cg-btn" (click)="closeForm()">{{ 'common.cancel' | translate }}</button>
        <p *ngIf="error" class="form-error">{{ error }}</p>
      </div>

      <div class="cg-panel-body">
        <div *ngIf="credentials.length === 0" class="cg-empty">{{ 'anthropicCredentials.empty' | translate }}</div>
        <div *ngFor="let c of credentials" class="list-row" style="padding: 8px 16px; cursor: default;">
          <app-icon style="opacity:.5;flex-shrink:0;">key</app-icon>
          <div class="row-main">
            <span class="row-title-line">
              <span class="row-title">{{ c.name }}</span>
              <app-copy-id class="row-code" [value]="c.code"></app-copy-id>
            </span>
            <span class="row-desc">{{ 'anthropicCredentials.usage' | translate:{ code: c.code } }}</span>
          </div>
          <div class="row-actions" *ngIf="canManage">
            <button class="cg-icon-btn" (click)="startEdit(c)" [cgTooltip]="'common.edit' | translate"
                    style="width:32px;height:32px;">
              <app-icon style="font-size:16px;width:16px;height:16px;">edit</app-icon>
            </button>
            <button class="cg-icon-btn" (click)="remove(c)" [cgTooltip]="'common.delete' | translate"
                    style="width:32px;height:32px;">
              <app-icon style="font-size:16px;width:16px;height:16px;">delete</app-icon>
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .add-form {
      display: flex;
      align-items: flex-end;
      gap: 10px;
      padding: 12px 18px;
      border-bottom: 1px solid var(--cg-border);
      flex-wrap: wrap;
    }
    .spacer { flex: 1 1 auto; }
    .row-title-line { display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .row-actions { display: flex; align-items: center; gap: 6px; }
    .form-error { width: 100%; margin: 0; font-size: 12px; color: #f87171; }
  `],
})
export class AnthropicCredentialsPanelComponent implements OnInit {
  @Input() projectId!: number;
  @Input() canManage = false;

  credentials: AnthropicCredential[] = [];
  formOpen = false;
  editing: AnthropicCredential | null = null;
  formName = '';
  formKey = '';
  error = '';

  constructor(
    private api: ApiService,
    private dialog: Dialog,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.load();
  }

  load(): void {
    this.api.listProjectAnthropicCredentials(this.projectId).subscribe(list => {
      this.credentials = list;
      this.cdr.markForCheck();
    });
  }

  startCreate(): void {
    this.editing = null;
    this.formName = '';
    this.formKey = '';
    this.error = '';
    this.formOpen = true;
  }

  startEdit(c: AnthropicCredential): void {
    this.editing = c;
    this.formName = c.name;
    this.formKey = '';
    this.error = '';
    this.formOpen = true;
  }

  closeForm(): void {
    this.formOpen = false;
    this.editing = null;
    this.error = '';
  }

  save(): void {
    const done = () => { this.closeForm(); this.load(); };
    const fail = (err: any) => {
      this.error = err?.error?.errors?.api_key?.[0]
        ? this.i18n.t('anthropicCredentials.invalidKey')
        : this.i18n.t('anthropicCredentials.saveError');
      this.cdr.markForCheck();
    };

    if (this.editing) {
      this.api.updateAnthropicCredential(this.projectId, this.editing.id, { name: this.formName, apiKey: this.formKey })
        .subscribe({ next: done, error: fail });
    } else {
      this.api.createAnthropicCredential(this.projectId, { name: this.formName, apiKey: this.formKey })
        .subscribe({ next: done, error: fail });
    }
  }

  remove(c: AnthropicCredential): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: c.name, kind: this.i18n.t('anthropicCredentials.kind') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (ok) this.api.deleteAnthropicCredential(this.projectId, c.id).subscribe(() => this.load());
    });
  }
}
