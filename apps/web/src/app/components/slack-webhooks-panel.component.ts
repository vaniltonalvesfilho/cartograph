import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Dialog } from '@angular/cdk/dialog';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { CopyIdComponent } from './copy-id.component';
import { DeleteConfirmDialogComponent } from './delete-confirm-dialog.component';
import { ApiService } from '../services/api.service';
import { SlackWebhook } from '../models';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

/**
 * Slack webhooks registered on a project. Any viewer sees name + code (the
 * DSL needs the code); creating, editing and deleting require Navigator+
 * (`can.manageSecrets`). The webhook URL is write-only: it is sent on save
 * and never displayed back.
 */
@Component({
  selector: 'app-slack-webhooks-panel',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective, CopyIdComponent, TranslatePipe,
  ],
  template: `
    <div class="cg-panel">
      <div class="cg-panel-header">
        <app-icon style="opacity:.6;">notifications_active</app-icon>
        <p class="cg-panel-title">{{ 'slackWebhooks.title' | translate }}</p>
        <p class="cg-panel-sub" style="margin-left:6px;">{{ 'slackWebhooks.hint' | translate }}</p>
        <span class="spacer"></span>
        <button *ngIf="canManage" class="cg-btn" (click)="startCreate()" style="font-size:13px;">
          <app-icon>add</app-icon> {{ 'slackWebhooks.add' | translate }}
        </button>
      </div>

      <!-- Create / edit form -->
      <div *ngIf="formOpen && canManage" class="add-form">
        <div class="cg-field" style="width:220px;">
          <label class="cg-label">{{ 'slackWebhooks.name' | translate }}</label>
          <input class="cg-input" [(ngModel)]="formName" [placeholder]="'slackWebhooks.namePlaceholder' | translate" />
        </div>
        <div class="cg-field" style="flex:1;min-width:260px;">
          <label class="cg-label">{{ 'slackWebhooks.url' | translate }}</label>
          <input class="cg-input" type="password" autocomplete="off" [(ngModel)]="formUrl"
                 [placeholder]="editing ? ('slackWebhooks.urlKeep' | translate) : 'https://hooks.slack.com/services/…'" />
        </div>
        <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="!formName || (!editing && !formUrl)">
          {{ 'common.save' | translate }}
        </button>
        <button class="cg-btn" (click)="closeForm()">{{ 'common.cancel' | translate }}</button>
        <p *ngIf="error" class="form-error">{{ error }}</p>
      </div>

      <div class="cg-panel-body">
        <div *ngIf="webhooks.length === 0" class="cg-empty">{{ 'slackWebhooks.empty' | translate }}</div>
        <div *ngFor="let w of webhooks" class="list-row" style="padding: 8px 16px; cursor: default;">
          <app-icon style="opacity:.5;flex-shrink:0;">tag</app-icon>
          <div class="row-main">
            <span class="row-title-line">
              <span class="row-title">{{ w.name }}</span>
              <app-copy-id class="row-code" [value]="w.code"></app-copy-id>
            </span>
            <span class="row-desc">{{ 'slackWebhooks.usage' | translate:{ code: w.code } }}</span>
          </div>
          <div class="row-actions" *ngIf="canManage">
            <button class="cg-icon-btn" (click)="startEdit(w)" [cgTooltip]="'common.edit' | translate"
                    style="width:32px;height:32px;">
              <app-icon style="font-size:16px;width:16px;height:16px;">edit</app-icon>
            </button>
            <button class="cg-icon-btn" (click)="remove(w)" [cgTooltip]="'common.delete' | translate"
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
export class SlackWebhooksPanelComponent implements OnInit {
  @Input() projectId!: number;
  @Input() canManage = false;

  webhooks: SlackWebhook[] = [];
  formOpen = false;
  editing: SlackWebhook | null = null;
  formName = '';
  formUrl = '';
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
    this.api.listProjectSlackWebhooks(this.projectId).subscribe(list => {
      this.webhooks = list;
      this.cdr.markForCheck();
    });
  }

  startCreate(): void {
    this.editing = null;
    this.formName = '';
    this.formUrl = '';
    this.error = '';
    this.formOpen = true;
  }

  startEdit(w: SlackWebhook): void {
    this.editing = w;
    this.formName = w.name;
    this.formUrl = '';
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
      this.error = err?.error?.errors?.url?.[0]
        ? this.i18n.t('slackWebhooks.invalidUrl')
        : this.i18n.t('slackWebhooks.saveError');
      this.cdr.markForCheck();
    };

    if (this.editing) {
      this.api.updateSlackWebhook(this.projectId, this.editing.id, { name: this.formName, url: this.formUrl })
        .subscribe({ next: done, error: fail });
    } else {
      this.api.createSlackWebhook(this.projectId, { name: this.formName, url: this.formUrl })
        .subscribe({ next: done, error: fail });
    }
  }

  remove(w: SlackWebhook): void {
    const ref = this.dialog.open(DeleteConfirmDialogComponent, {
      data: { name: w.name, kind: this.i18n.t('slackWebhooks.kind') }, width: '460px',
    });
    ref.closed.subscribe(ok => {
      if (ok) this.api.deleteSlackWebhook(this.projectId, w.id).subscribe(() => this.load());
    });
  }
}
