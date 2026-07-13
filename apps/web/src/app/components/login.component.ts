import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ViewChild, ElementRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, ActivatedRoute, RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { AuthService } from '../services/auth.service';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { ElectronService } from '../services/electron.service';

@Component({
  selector: 'app-login',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, RouterLink, IconComponent, TranslatePipe],
  template: `
    <div class="login-shell">
      <div class="login-card">
        <div class="login-brand">
          <app-icon class="brand-ic">map</app-icon>
          <span class="login-brand-name">Cartograph</span>
        </div>
        <p class="login-subtitle">Distributed Task Runner</p>

        <!-- Step 1: credentials -->
        <ng-container *ngIf="step === 'credentials'">
          <div class="cg-field">
            <label class="cg-label">{{ 'login.email' | translate }}</label>
            <input class="cg-input" type="email" [(ngModel)]="email" (keydown.enter)="submit()" autofocus />
          </div>

          <div class="cg-field">
            <label class="cg-label">{{ 'login.password' | translate }}</label>
            <div class="pwd-wrap">
              <input class="cg-input" [type]="showPwd ? 'text' : 'password'" [(ngModel)]="password" (keydown.enter)="submit()" />
              <button class="pwd-toggle" (click)="showPwd = !showPwd" type="button" tabindex="-1">
                <app-icon>{{ showPwd ? 'visibility_off' : 'visibility' }}</app-icon>
              </button>
            </div>
          </div>

          <p *ngIf="error" class="login-error">{{ error }}</p>

          <button class="cg-btn cg-btn-primary login-submit"
            (click)="submit()" [disabled]="loading">
            {{ (loading ? 'login.signingIn' : 'login.signIn') | translate }}
          </button>
        </ng-container>

        <!-- Step 2: TOTP -->
        <ng-container *ngIf="step === 'totp'">
          <div class="totp-icon">
            <app-icon>security</app-icon>
          </div>
          <p class="totp-prompt">{{ 'login.totpPrompt' | translate }}</p>

          <div class="cg-field">
            <label class="cg-label">{{ 'login.totpCode' | translate }}</label>
            <input #totpInput class="cg-input" type="text" inputmode="numeric" maxlength="6"
              autocomplete="one-time-code" [(ngModel)]="totpCode"
              (keydown.enter)="submitTotp()" />
          </div>

          <p *ngIf="error" class="login-error">{{ error }}</p>

          <button class="cg-btn cg-btn-primary login-submit"
            (click)="submitTotp()" [disabled]="loading || totpCode.length < 6">
            {{ (loading ? 'login.signingIn' : 'login.totpVerify') | translate }}
          </button>

          <button class="cg-btn cg-btn-ghost login-back" (click)="backToCredentials()">
            {{ 'login.totpBack' | translate }}
          </button>
        </ng-container>

        <!-- Desktop only: change the backend this client talks to -->
        <a *ngIf="electron.isElectron" class="login-server-link" [routerLink]="['/settings/server']">
          <app-icon>dns</app-icon>
          <span>{{ 'server.title' | translate }}</span>
        </a>
      </div>
    </div>
  `,
  styles: [`
    .login-shell {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: var(--cg-content-bg);
    }
    .login-card {
      width: 380px;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      border-radius: 14px;
      padding: 36px 32px 32px;
      display: flex;
      flex-direction: column;
      gap: 14px;
    }
    .login-brand {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 2px;
    }
    .brand-ic { font-size: 36px; color: var(--cg-accent); }
    .pwd-wrap { position: relative; display: flex; align-items: center; }
    .pwd-wrap .cg-input { padding-right: 40px; }
    .pwd-toggle {
      position: absolute; right: 4px;
      display: inline-flex; align-items: center; justify-content: center;
      width: 30px; height: 30px; border: none; background: transparent;
      color: var(--cg-text-muted); cursor: pointer; border-radius: 6px;
      app-icon { font-size: 18px; }
      &:hover { color: var(--cg-text); background: var(--cg-surface-2); }
    }
    .login-submit { width: 100%; height: 44px; font-size: 15px; }
    .login-back { width: 100%; margin-top: 4px; }
    .login-server-link {
      display: inline-flex; align-items: center; gap: 6px;
      align-self: center; margin-top: 2px;
      font-size: 12px; color: var(--cg-text-muted); cursor: pointer;
      text-decoration: none;
      app-icon { font-size: 15px; }
      &:hover { color: var(--cg-accent); }
    }
    .login-brand-name {
      font-size: 24px;
      font-weight: 800;
      color: var(--cg-text);
      letter-spacing: -0.3px;
    }
    .login-subtitle {
      margin: 0 0 6px;
      font-size: 13px;
      color: var(--cg-text-muted);
    }
    .login-error {
      margin: 0;
      font-size: 13px;
      color: #f87171;
    }
    .totp-icon {
      display: flex;
      justify-content: center;
      margin: 4px 0;
      app-icon { font-size: 40px; color: var(--cg-accent); }
    }
    .totp-prompt {
      margin: 0;
      font-size: 14px;
      color: var(--cg-text-muted);
      text-align: center;
    }
  `],
})
export class LoginComponent {
  @ViewChild('totpInput') totpInputRef?: ElementRef<HTMLInputElement>;

  step: 'credentials' | 'totp' = 'credentials';
  email = '';
  password = '';
  showPwd = false;
  totpCode = '';
  pendingToken = '';
  loading = false;
  error = '';

  constructor(
    private auth: AuthService,
    private router: Router,
    private route: ActivatedRoute,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
    public electron: ElectronService,
  ) {}

  submit(): void {
    if (!this.email || !this.password) return;
    this.loading = true;
    this.error = '';
    this.auth.login(this.email, this.password).subscribe({
      next: res => {
        if (res.requireTotp) {
          this.pendingToken = res.pendingToken!;
          this.step = 'totp';
          this.loading = false;
          this.cdr.markForCheck();
          setTimeout(() => this.totpInputRef?.nativeElement.focus(), 50);
        } else {
          const returnUrl = this.route.snapshot.queryParams['returnUrl'] || '/';
          this.router.navigateByUrl(returnUrl);
        }
      },
      error: () => {
        this.loading = false;
        this.error = this.i18n.t('login.invalid');
        this.cdr.markForCheck();
      },
    });
  }

  submitTotp(): void {
    if (this.totpCode.length < 6) return;
    this.loading = true;
    this.error = '';
    this.auth.verifyTotpLogin(this.pendingToken, this.totpCode).subscribe({
      next: () => {
        const returnUrl = this.route.snapshot.queryParams['returnUrl'] || '/';
        this.router.navigateByUrl(returnUrl);
      },
      error: () => {
        this.loading = false;
        this.totpCode = '';
        this.error = this.i18n.t('login.totpError');
        this.cdr.markForCheck();
      },
    });
  }

  backToCredentials(): void {
    this.step = 'credentials';
    this.totpCode = '';
    this.pendingToken = '';
    this.error = '';
  }
}
