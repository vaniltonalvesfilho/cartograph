import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TranslatePipe } from '../services/translate.pipe';
import { TranslationService } from '../services/translation.service';
import { ElectronService } from '../services/electron.service';

// Desktop-only screen to point the app at a Cartograph backend. Saving persists
// the URL through the Electron bridge, which reloads the window so every service
// re-reads the injected config. Reachable from the login screen and the user menu.
@Component({
  selector: 'app-server-settings',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, IconComponent, TranslatePipe],
  template: `
    <div class="srv-shell">
      <div class="srv-card">
        <div class="srv-head">
          <app-icon class="srv-ic">dns</app-icon>
          <h2 class="srv-title">{{ 'server.title' | translate }}</h2>
        </div>
        <p class="srv-desc">{{ 'server.desc' | translate }}</p>

        <div class="cg-field">
          <label class="cg-label">{{ 'server.url' | translate }}</label>
          <input class="cg-input" type="url" placeholder="http://localhost:8080"
                 [(ngModel)]="url" (keydown.enter)="save()" autofocus />
        </div>

        <p *ngIf="error" class="srv-error">{{ error }}</p>

        <button class="cg-btn cg-btn-primary srv-save" (click)="save()" [disabled]="saving">
          {{ 'server.save' | translate }}
        </button>
        <button class="cg-btn cg-btn-ghost srv-cancel" (click)="cancel()">
          {{ 'server.cancel' | translate }}
        </button>
      </div>
    </div>
  `,
  styles: [`
    .srv-shell {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: var(--cg-content-bg);
    }
    .srv-card {
      width: 400px;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      border-radius: 14px;
      padding: 32px;
      display: flex;
      flex-direction: column;
      gap: 12px;
    }
    .srv-head { display: flex; align-items: center; gap: 10px; }
    .srv-ic { font-size: 28px; color: var(--cg-accent); }
    .srv-title { margin: 0; font-size: 19px; font-weight: 700; color: var(--cg-text); }
    .srv-desc { margin: 0 0 6px; font-size: 13px; color: var(--cg-text-muted); }
    .srv-error { margin: 0; font-size: 13px; color: #f87171; }
    .srv-save { width: 100%; height: 42px; font-size: 15px; }
    .srv-cancel { width: 100%; }
  `],
})
export class ServerSettingsComponent implements OnInit {
  url = '';
  saving = false;
  error = '';

  constructor(
    private electron: ElectronService,
    private location: Location,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  async ngOnInit(): Promise<void> {
    this.url = (await this.electron.getServerUrl()) || 'http://localhost:8080';
    this.cdr.markForCheck();
  }

  async save(): Promise<void> {
    const url = this.url.trim().replace(/\/+$/, '');
    if (!/^https?:\/\/.+/i.test(url)) {
      this.error = this.i18n.t('server.invalid');
      return;
    }
    this.saving = true;
    // setServerUrl reloads the window in the main process; nothing runs after it.
    await this.electron.setServerUrl(url);
  }

  cancel(): void {
    this.location.back();
  }
}
