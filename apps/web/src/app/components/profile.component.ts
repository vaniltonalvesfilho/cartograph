import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit, ViewChild, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import * as QRCode from 'qrcode';
import { ApiService } from '../services/api.service';
import { AuthService } from '../services/auth.service';
import { ApiToken, User } from '../models';
import { TranslatePipe } from '../services/translate.pipe';
import { TranslationService } from '../services/translation.service';

@Component({
  selector: 'app-profile',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective,
    TranslatePipe,
  ],
  template: `
    <div class="page-wrap">
      <div class="page-header">
        <app-icon class="page-icon">person</app-icon>
        <div>
          <h2 class="page-title">{{ 'profile.title' | translate }}</h2>
          <p class="page-subtitle" *ngIf="user">{{ user.name }} · {{ user.email }}</p>
        </div>
      </div>

      <!-- 2FA panel -->
      <div class="cg-panel section-card">
        <div class="card-head">
          <h3 class="card-title">{{ 'profile.twoFactor' | translate }}</h3>
          <p class="card-sub">{{ 'profile.twoFactorDesc' | translate }}</p>
        </div>
        <div class="card-body">

          <!-- Status badge -->
          <div class="status-row">
            <app-icon [class.enabled]="user?.totpEnabled" [class.disabled]="!user?.totpEnabled">
              {{ user?.totpEnabled ? 'verified_user' : 'shield' }}
            </app-icon>
            <span [class.enabled-text]="user?.totpEnabled" [class.disabled-text]="!user?.totpEnabled">
              {{ (user?.totpEnabled ? 'profile.twoFactorEnabled' : 'profile.twoFactorDisabled') | translate }}
            </span>
          </div>

          <hr class="cg-divider">

          <!-- ENABLED state -->
          <ng-container *ngIf="user?.totpEnabled">
            <p class="info-text">{{ 'profile.scanQr' | translate }}</p>
            <button class="cg-btn cg-btn-danger" (click)="confirmDisable()">
              <app-icon>lock_open</app-icon>
              {{ 'profile.disable2fa' | translate }}
            </button>
          </ng-container>

          <!-- DISABLED + no setup in progress -->
          <ng-container *ngIf="!user?.totpEnabled && setupStep === 'idle'">
            <button class="cg-btn cg-btn-primary" (click)="startSetup()" [disabled]="loading">
              <app-icon>security</app-icon>
              {{ 'profile.enable2fa' | translate }}
            </button>
          </ng-container>

          <!-- SETUP in progress -->
          <ng-container *ngIf="setupStep === 'scan'">
            <p class="info-text">{{ 'profile.scanQr' | translate }}</p>

            <div class="qr-wrap">
              <canvas #qrCanvas></canvas>
            </div>

            <p class="manual-label">{{ 'profile.orManual' | translate }}</p>
            <code class="secret-code">{{ totpSecret }}</code>

            <div class="cg-field" style="margin-top:16px;">
              <label class="cg-label">{{ 'profile.confirmCode' | translate }}</label>
              <input class="cg-input" type="text" inputmode="numeric" maxlength="6"
                autocomplete="one-time-code" [(ngModel)]="confirmCode" />
            </div>

            <p *ngIf="error" class="error-text">{{ error }}</p>

            <div class="btn-row">
              <button class="cg-btn cg-btn-primary"
                (click)="confirmEnable()" [disabled]="loading || confirmCode.length < 6">
                {{ 'profile.activate' | translate }}
              </button>
              <button class="cg-btn cg-btn-ghost" (click)="cancelSetup()">{{ 'login.totpBack' | translate }}</button>
            </div>
          </ng-container>

          <!-- Success flash -->
          <div *ngIf="successMsg" class="success-text">
            <app-icon>check_circle</app-icon> {{ successMsg }}
          </div>

        </div>
      </div>

      <!-- API Tokens panel -->
      <div class="cg-panel section-card">
        <div class="card-head">
          <h3 class="card-title">{{ 'profile.apiTokens' | translate }}</h3>
          <p class="card-sub">{{ 'profile.apiTokensDesc' | translate }}</p>
        </div>
        <div class="card-body">

          <!-- New raw token alert (shown once after creation) -->
          <div *ngIf="newRawToken" class="token-reveal">
            <div class="token-reveal-header">
              <app-icon>warning</app-icon>
              {{ 'profile.tokenOnce' | translate }}
            </div>
            <div class="token-value-row">
              <code class="token-value">{{ newRawToken }}</code>
              <button class="cg-icon-btn" (click)="copyToken()" [cgTooltip]="'gql.copy' | translate">
                <app-icon>{{ copied ? 'check' : 'content_copy' }}</app-icon>
              </button>
            </div>
            <button class="cg-btn cg-btn-ghost" (click)="newRawToken = ''; copied = false" style="margin-top:8px;">
              {{ 'profile.tokenDone' | translate }}
            </button>
          </div>

          <!-- Create form -->
          <ng-container *ngIf="!newRawToken">
            <div *ngIf="!creatingToken">
              <button class="cg-btn" (click)="creatingToken = true">
                <app-icon>add</app-icon>
                {{ 'profile.newToken' | translate }}
              </button>
            </div>

            <div *ngIf="creatingToken" class="create-form">
              <div class="cg-field" style="flex:1;">
                <label class="cg-label">{{ 'profile.tokenName' | translate }}</label>
                <input class="cg-input" [(ngModel)]="newTokenName" (keydown.enter)="createToken()"
                       [placeholder]="'profile.tokenNamePlaceholder' | translate" />
              </div>
              <div class="cg-field" style="width:190px;">
                <label class="cg-label">{{ 'profile.tokenExpiry' | translate }}</label>
                <input class="cg-input" type="date" [(ngModel)]="newTokenExpiry" />
              </div>
              <button class="cg-btn cg-btn-primary" (click)="createToken()"
                      [disabled]="tokenLoading || !newTokenName.trim()">
                {{ 'common.create' | translate }}
              </button>
              <button class="cg-btn cg-btn-ghost" (click)="creatingToken = false; newTokenName = ''; newTokenExpiry = ''">
                {{ 'common.cancel' | translate }}
              </button>
            </div>
          </ng-container>

          <!-- Token list -->
          <div *ngIf="tokens.length > 0" class="token-list">
            <hr class="cg-divider">
            <div *ngFor="let t of tokens" class="token-row">
              <div class="token-info">
                <span class="token-prefix"><code>{{ t.prefix }}…</code></span>
                <span class="token-name">{{ t.name }}</span>
                <span class="token-meta">
                  {{ 'profile.tokenCreated' | translate }}: {{ t.createdAt | date:'dd/MM/yyyy' }}
                </span>
                <span *ngIf="t.lastUsedAt" class="token-meta">
                  {{ 'profile.tokenLastUsed' | translate }}: {{ t.lastUsedAt | date:'dd/MM/yyyy HH:mm' }}
                </span>
                <span *ngIf="t.expiresAt" class="token-meta"
                      [class.token-expired]="isExpired(t.expiresAt)">
                  {{ 'profile.tokenExpires' | translate }}: {{ t.expiresAt | date:'dd/MM/yyyy' }}
                </span>
              </div>
              <button class="cg-icon-btn" class="revoke-btn" (click)="revokeToken(t)"
                      [cgTooltip]="'profile.tokenRevoke' | translate">
                <app-icon>delete</app-icon>
              </button>
            </div>
          </div>

          <div *ngIf="tokens.length === 0 && !creatingToken && !newRawToken" class="empty-tokens">
            {{ 'profile.noTokens' | translate }}
          </div>

        </div>
      </div>
    </div>
  `,
  styles: [`
    .page-wrap { max-width: 640px; margin: 0 auto; padding: 24px 16px; }
    .page-header { display: flex; align-items: flex-start; gap: 12px; margin-bottom: 24px; }
    .page-icon { font-size: 32px; width: 32px; height: 32px; color: var(--cg-accent); margin-top: 2px; }
    .page-title { margin: 0; font-size: 20px; font-weight: 700; color: var(--cg-text); }
    .page-subtitle { margin: 2px 0 0; font-size: 13px; color: var(--cg-text-muted); }
    .section-card { margin-bottom: 20px; padding: 18px; }
    .card-head { margin-bottom: 4px; }
    .card-title { margin: 0; font-size: 16px; font-weight: 700; color: var(--cg-text); }
    .card-sub { margin: 2px 0 0; font-size: 13px; color: var(--cg-text-muted); }
    .card-body { padding-top: 16px; }

    .status-row {
      display: flex; align-items: center; gap: 8px;
      app-icon { font-size: 20px; width: 20px; height: 20px; }
      app-icon.enabled { color: #4ade80; }
      app-icon.disabled { color: var(--cg-text-muted); }
    }
    .enabled-text { color: #4ade80; font-weight: 600; font-size: 14px; }
    .disabled-text { color: var(--cg-text-muted); font-size: 14px; }

    .qr-wrap {
      display: flex;
      justify-content: center;
      margin: 16px 0;
      canvas { border-radius: 8px; background: #fff; padding: 8px; }
    }
    .manual-label { margin: 0 0 6px; font-size: 13px; color: var(--cg-text-muted); }
    .secret-code {
      display: block;
      background: var(--cg-surface-1, #1e2530);
      border: 1px solid var(--cg-border);
      border-radius: 6px;
      padding: 10px 14px;
      font-family: monospace;
      font-size: 14px;
      letter-spacing: 2px;
      word-break: break-all;
      color: var(--cg-text);
    }
    .btn-row { display: flex; gap: 8px; align-items: center; margin-top: 8px; }
    .info-text { margin: 0 0 12px; font-size: 13px; color: var(--cg-text-muted); line-height: 1.5; }
    .error-text { color: #f87171; font-size: 13px; margin: 4px 0; }
    .success-text {
      display: flex; align-items: center; gap: 6px;
      color: #4ade80; font-size: 14px; margin-top: 12px;
      app-icon { font-size: 18px; width: 18px; height: 18px; }
    }

    .token-reveal {
      background: rgba(251, 191, 36, 0.08);
      border: 1px solid rgba(251, 191, 36, 0.3);
      border-radius: 8px;
      padding: 14px 16px;
      margin-bottom: 16px;
    }
    .token-reveal-header {
      display: flex; align-items: center; gap: 6px;
      font-weight: 600; font-size: 13px; color: #fbbf24; margin-bottom: 10px;
      app-icon { font-size: 18px; width: 18px; height: 18px; }
    }
    .token-value-row {
      display: flex; align-items: center; gap: 8px;
    }
    .token-value {
      flex: 1;
      display: block;
      background: var(--cg-content-bg);
      border: 1px solid var(--cg-border);
      border-radius: 6px;
      padding: 8px 12px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      word-break: break-all;
      color: var(--cg-text);
    }

    .create-form {
      display: flex; align-items: center; flex-wrap: wrap; gap: 10px; margin-bottom: 4px;
    }

    .token-list { display: flex; flex-direction: column; gap: 2px; }
    .token-row {
      display: flex; align-items: center; gap: 12px;
      padding: 10px 8px; border-radius: 6px;
      &:hover { background: var(--cg-content-bg); }
      &:hover .revoke-btn { opacity: 1; }
    }
    .token-info { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; flex: 1; min-width: 0; }
    .token-prefix code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11px;
      background: var(--cg-content-bg);
      border: 1px solid var(--cg-border);
      padding: 2px 6px;
      border-radius: 4px;
    }
    .token-name { font-size: 13px; font-weight: 600; color: var(--cg-text); }
    .token-meta { font-size: 11px; color: var(--cg-text-muted); }
    .token-expired { color: #f87171; }
    .revoke-btn { opacity: 0; transition: opacity 0.12s; color: var(--cg-text-muted);
      &:hover app-icon { color: #f87171; } }
    .empty-tokens { font-size: 13px; color: var(--cg-text-muted); padding: 8px 0; }
  `],
})
export class ProfileComponent implements OnInit {
  @ViewChild('qrCanvas') qrCanvasRef?: ElementRef<HTMLCanvasElement>;

  user: User | null = null;
  setupStep: 'idle' | 'scan' = 'idle';
  totpSecret = '';
  totpUri = '';
  confirmCode = '';
  error = '';
  successMsg = '';
  loading = false;

  // API Tokens
  tokens: ApiToken[] = [];
  creatingToken = false;
  newTokenName = '';
  newTokenExpiry = '';
  newRawToken = '';
  copied = false;
  tokenLoading = false;

  constructor(
    private api: ApiService,
    private auth: AuthService,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.auth.currentUser$.subscribe(u => { this.user = u; this.cdr.markForCheck(); });
    this.loadTokens();
  }

  loadTokens(): void {
    this.api.listApiTokens().subscribe({ next: ({ tokens }) => { this.tokens = tokens; this.cdr.markForCheck(); } });
  }

  createToken(): void {
    if (!this.newTokenName.trim()) return;
    this.tokenLoading = true;
    const expiry = this.newTokenExpiry
      ? new Date(this.newTokenExpiry + 'T23:59:59Z').toISOString()
      : undefined;
    this.api.createApiToken(this.newTokenName.trim(), expiry).subscribe({
      next: ({ token, rawToken }) => {
        this.tokens = [token, ...this.tokens];
        this.newRawToken = rawToken;
        this.newTokenName = '';
        this.newTokenExpiry = '';
        this.creatingToken = false;
        this.tokenLoading = false;
        this.cdr.markForCheck();
      },
      error: () => { this.tokenLoading = false; this.cdr.markForCheck(); },
    });
  }

  revokeToken(token: ApiToken): void {
    if (!confirm(this.i18n.t('profile.tokenRevokeConfirm'))) return;
    this.api.revokeApiToken(token.id).subscribe({
      next: () => { this.tokens = this.tokens.filter(t => t.id !== token.id); this.cdr.markForCheck(); },
    });
  }

  copyToken(): void {
    navigator.clipboard.writeText(this.newRawToken).then(() => {
      this.copied = true;
      this.cdr.markForCheck();
      setTimeout(() => { this.copied = false; this.cdr.markForCheck(); }, 2000);
    });
  }

  isExpired(expiresAt: string | null): boolean {
    return !!expiresAt && new Date(expiresAt) < new Date();
  }

  startSetup(): void {
    this.loading = true;
    this.error = '';
    this.api.getTotpSetup().subscribe({
      next: ({ secret, uri }) => {
        this.totpSecret = secret;
        this.totpUri = uri;
        this.setupStep = 'scan';
        this.loading = false;
        this.cdr.markForCheck();
        // Wait for Angular to render the *ngIf canvas before drawing QR
        setTimeout(() => {
          if (this.qrCanvasRef) {
            QRCode.toCanvas(this.qrCanvasRef.nativeElement, uri, { width: 200, margin: 1 });
          }
        }, 50);
      },
      error: () => {
        this.loading = false;
        this.error = this.i18n.t('login.totpError');
        this.cdr.markForCheck();
      },
    });
  }

  confirmEnable(): void {
    if (this.confirmCode.length < 6) return;
    this.loading = true;
    this.error = '';
    this.api.enableTotp(this.confirmCode).subscribe({
      next: () => {
        this.setupStep = 'idle';
        this.successMsg = this.i18n.t('profile.twoFactorSuccess');
        this.loading = false;
        this.auth.patchCurrentUser({ totpEnabled: true });
        this.cdr.markForCheck();
        setTimeout(() => { this.successMsg = ''; this.cdr.markForCheck(); }, 4000);
      },
      error: () => {
        this.loading = false;
        this.confirmCode = '';
        this.error = this.i18n.t('login.totpError');
        this.cdr.markForCheck();
      },
    });
  }

  cancelSetup(): void {
    this.setupStep = 'idle';
    this.confirmCode = '';
    this.error = '';
  }

  confirmDisable(): void {
    if (!confirm(this.i18n.t('profile.disableConfirm'))) return;
    this.loading = true;
    this.api.disableTotp().subscribe({
      next: () => {
        this.loading = false;
        this.auth.patchCurrentUser({ totpEnabled: false });
        this.cdr.markForCheck();
      },
      error: () => { this.loading = false; this.cdr.markForCheck(); },
    });
  }
}
