import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { SmtpSettings } from '../models';
import { IconComponent } from './icon.component';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { extractApiError } from '../utils/http-error.util';

@Component({
  selector: 'app-admin-smtp',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, IconComponent, TranslatePipe],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">mail</app-icon>
      <div>
        <h2 class="page-title">{{ 'smtp.title' | translate }}</h2>
        <p class="page-subtitle">{{ 'smtp.subtitle' | translate }}</p>
      </div>
    </div>

    <div class="cg-panel" *ngIf="form">
      <div class="cg-panel-body padded">
        <!-- Enabled toggle -->
        <label class="check-row enable-row">
          <input type="checkbox" [(ngModel)]="form.enabled" />
          <span>{{ 'smtp.enabled' | translate }}</span>
        </label>
        <p class="field-hint enable-hint">{{ 'smtp.enabledHint' | translate }}</p>

        <div class="section-divider">
          <span class="section-label"><app-icon>dns</app-icon>{{ 'smtp.server' | translate }}</span>
        </div>

        <div class="form-grid">
          <div class="cg-field">
            <label class="cg-label">{{ 'smtp.host' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.host" placeholder="smtp.exemplo.com">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'smtp.port' | translate }}</label>
            <input class="cg-input" type="number" [(ngModel)]="form.port">
            <span class="field-hint">{{ 'smtp.portHint' | translate }}</span>
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'smtp.tls' | translate }}</label>
            <div class="select-wrap">
              <select class="cg-select" [(ngModel)]="form.tls">
                <option value="if_available">{{ 'smtp.tlsIfAvailable' | translate }}</option>
                <option value="always">{{ 'smtp.tlsAlways' | translate }}</option>
                <option value="never">{{ 'smtp.tlsNever' | translate }}</option>
              </select>
              <app-icon class="select-arrow">expand_more</app-icon>
            </div>
          </div>
          <div class="ssl-row">
            <label class="check-row">
              <input type="checkbox" [(ngModel)]="form.auth" />
              <span>{{ 'smtp.auth' | translate }}</span>
            </label>
          </div>
          <div class="cg-field" *ngIf="form.auth">
            <label class="cg-label">{{ 'smtp.username' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.username" autocomplete="off">
          </div>
          <div class="cg-field" *ngIf="form.auth">
            <label class="cg-label">{{ 'smtp.password' | translate }}</label>
            <input class="cg-input" type="password" [(ngModel)]="password" autocomplete="new-password"
                   [placeholder]="form.passwordSet ? ('smtp.passwordHint' | translate) : ''">
          </div>
        </div>

        <div class="section-divider">
          <span class="section-label"><app-icon>outgoing_mail</app-icon>{{ 'smtp.sender' | translate }}</span>
        </div>

        <div class="form-grid">
          <div class="cg-field">
            <label class="cg-label">{{ 'smtp.fromName' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.fromName" placeholder="Cartograph">
          </div>
          <div class="cg-field">
            <label class="cg-label">{{ 'smtp.fromEmail' | translate }}</label>
            <input class="cg-input" [(ngModel)]="form.fromEmail" placeholder="no-reply@exemplo.com">
          </div>
        </div>

        <p class="security-note">
          <app-icon>lock</app-icon>
          {{ 'smtp.securityNote' | translate }}
        </p>
      </div>

      <div class="cg-panel-footer">
        <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="saving">
          <span *ngIf="saving" class="cg-spinner" style="width:14px;height:14px;"></span>
          {{ 'common.save' | translate }}
        </button>
        <button class="cg-btn" (click)="sendTest()" [disabled]="testing || !form.enabled">
          <span *ngIf="testing" class="cg-spinner" style="width:14px;height:14px;"></span>
          <app-icon *ngIf="!testing">send</app-icon>
          {{ 'smtp.sendTest' | translate }}
        </button>
        <span *ngIf="testResult" class="test-result"
              [class.ok]="testResult.status === 'ok'"
              [class.err]="testResult.status === 'error'">
          <app-icon>{{ testResult.status === 'ok' ? 'check_circle' : 'error' }}</app-icon>
          {{ testResult.status === 'ok'
              ? ('smtp.testOk' | translate:{ email: testResult.sentTo })
              : ('smtp.testError' | translate:{ error: testResult.error }) }}
        </span>
        <span *ngIf="saved" class="test-result ok"><app-icon>check_circle</app-icon>{{ 'common.saved' | translate }}</span>
        <span *ngIf="saveError" class="test-result err"><app-icon>error</app-icon>{{ saveError }}</span>
      </div>
    </div>
  `,
  styles: [`
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); opacity: 0.9; }
    .form-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px 16px; }
    .select-wrap { position: relative; display: flex; align-items: center; }
    .select-wrap .cg-select { flex: 1; padding-right: 28px; }
    .select-arrow { position: absolute; right: 6px; font-size: 16px; pointer-events: none; opacity: .5; }
    .check-row { display: flex; align-items: center; gap: 8px; font-size: 14px; cursor: pointer; }
    .check-row input[type="checkbox"] { width: 15px; height: 15px; cursor: pointer; accent-color: var(--cg-accent); }
    .enable-row { font-weight: 600; }
    .enable-hint { margin: 4px 0 0 23px; }
    .ssl-row { grid-column: 1 / -1; padding: 2px 0; }
    .section-divider { display: flex; align-items: center; gap: 8px; margin: 16px 0 10px;
                       border-top: 1px solid var(--cg-border); padding-top: 14px; }
    .section-label { display: flex; align-items: center; gap: 6px; font-size: 13px;
                     font-weight: 600; color: var(--cg-text-muted); }
    .section-label app-icon { font-size: 16px; width: 16px; height: 16px; }
    .field-hint { font-size: 11px; color: var(--cg-text-muted); }
    .cg-panel-footer { padding: 12px 16px; display: flex; gap: 8px; align-items: center;
                       border-top: 1px solid var(--cg-border); }
    .padded { padding: 16px; }
    .security-note { display: flex; align-items: center; gap: 6px; margin-top: 16px;
                     font-size: 12px; color: var(--cg-text-muted); }
    .security-note app-icon { font-size: 15px; width: 15px; height: 15px; }
    .test-result { display: inline-flex; align-items: center; gap: 4px; font-size: 12px; margin-left: 4px; }
    .test-result.ok { color: #4ade80; }
    .test-result.err { color: #f87171; }
    .test-result app-icon { font-size: 15px; width: 15px; height: 15px; }
  `],
})
export class AdminSmtpComponent implements OnInit {
  form: SmtpSettings | null = null;
  password = '';
  saving = false;
  testing = false;
  saved = false;
  saveError: string | null = null;
  testResult: { status: string; sentTo?: string; error?: string } | null = null;

  constructor(
    private api: ApiService,
    private nav: NavContextService,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('smtp.title') }]);
    this.api.getSmtpSettings().subscribe(s => { this.form = s; this.cdr.markForCheck(); });
  }

  save(): void {
    if (!this.form) return;
    this.saving = true;
    this.saved = false;
    this.saveError = null;
    this.testResult = null;

    // Keys are snake_case to match the backend Ecto changeset fields.
    const attrs: Record<string, unknown> = {
      host: this.form.host,
      port: this.form.port,
      username: this.form.username,
      from_name: this.form.fromName,
      from_email: this.form.fromEmail,
      tls: this.form.tls,
      auth: this.form.auth,
      enabled: this.form.enabled,
    };
    // Only send the password when the admin actually typed one — a blank value
    // keeps the stored password (the backend drops blanks too).
    if (this.password) attrs['password'] = this.password;

    this.api.updateSmtpSettings(attrs).subscribe({
      next: (s) => {
        this.form = s;
        this.password = '';
        this.saving = false;
        this.saved = true;
        this.cdr.markForCheck();
      },
      error: (err) => {
        this.saving = false;
        this.saveError = this.extractError(err);
        this.cdr.markForCheck();
      },
    });
  }

  private extractError(err: any): string {
    return extractApiError(err, this.i18n.t('common.error'));
  }

  sendTest(): void {
    this.testing = true;
    this.testResult = null;
    this.api.sendSmtpTest().subscribe({
      next: (res) => { this.testResult = res; this.testing = false; this.cdr.markForCheck(); },
      error: (err) => {
        // Surface the backend's message when present (e.g. an SMTP 535 reply),
        // otherwise fall back to a transport-level hint.
        const msg = err?.error?.error || err?.error?.message || err?.message || 'request failed';
        this.testResult = { status: 'error', error: msg };
        this.testing = false;
        this.cdr.markForCheck();
      },
    });
  }
}
