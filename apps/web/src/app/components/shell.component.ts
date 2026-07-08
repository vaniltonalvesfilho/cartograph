import { ChangeDetectionStrategy, Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterOutlet, RouterLink } from '@angular/router';
import { CdkMenu, CdkMenuItem, CdkMenuTrigger } from '@angular/cdk/menu';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { ThemeService } from '../services/theme.service';
import { AuthService } from '../services/auth.service';
import { ElectronService } from '../services/electron.service';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { SidebarComponent } from './sidebar.component';
import { BreadcrumbComponent } from './breadcrumb.component';

@Component({
  selector: 'app-shell',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterOutlet, RouterLink,
    CdkMenu, CdkMenuItem, CdkMenuTrigger,
    IconComponent, TooltipDirective,
    SidebarComponent, BreadcrumbComponent, TranslatePipe,
  ],
  template: `
    <div class="app-shell">
      <aside class="sidebar" [class.collapsed]="collapsed()">
        <div class="sidebar-brand">
          <app-icon class="brand-icon">map</app-icon>
          <span class="brand-name" *ngIf="!collapsed()">Cartograph</span>
        </div>
        <app-sidebar [collapsed]="collapsed()"></app-sidebar>
        <button class="sidebar-toggle-btn" (click)="toggleSidebar()"
                [cgTooltip]="collapsed() ? (i18n.t('sidebar.expand')) : ''"
                cgTooltipPos="after">
          <app-icon>{{ collapsed() ? 'chevron_right' : 'chevron_left' }}</app-icon>
        </button>
      </aside>

      <div class="content-col">
        <header class="topbar">
          <app-breadcrumb></app-breadcrumb>
          <span class="spacer"></span>

          <ng-container *ngIf="auth.currentUser$ | async as u">
            <button class="user-menu-trigger" [cdkMenuTriggerFor]="userMenu">
              <app-icon class="um-person">person</app-icon>
              <span class="um-name">{{ u.name }}</span>
              <span *ngIf="u.isAdmin" class="admin-badge">{{ 'topbar.admin' | translate }}</span>
              <app-icon *ngIf="u.totpEnabled" class="um-totp">verified_user</app-icon>
              <app-icon class="um-chevron">expand_more</app-icon>
            </button>

            <ng-template #userMenu>
              <div cdkMenu class="cg-menu user-menu">
                <div class="menu-user-header">
                  <div class="menu-user-name">{{ u.name }}</div>
                  <div *ngIf="u.isAdmin" class="menu-user-role">{{ 'topbar.admin' | translate }}</div>
                </div>

                <div class="cg-menu-sep"></div>

                <button cdkMenuItem class="cg-menu-item" [routerLink]="['/profile']">
                  <app-icon>person</app-icon>
                  <span>{{ 'topbar.profile' | translate }}</span>
                </button>
                <button cdkMenuItem class="cg-menu-item" [routerLink]="['/docs']">
                  <app-icon>menu_book</app-icon>
                  <span>{{ 'sidebar.docs' | translate }}</span>
                </button>
                <button cdkMenuItem class="cg-menu-item" [routerLink]="['/graphql']">
                  <app-icon>hub</app-icon>
                  <span>GraphQL</span>
                </button>
                <button *ngIf="u.isAdmin" cdkMenuItem class="cg-menu-item" [routerLink]="['/admin/users']">
                  <app-icon>manage_accounts</app-icon>
                  <span>{{ 'topbar.manageUsers' | translate }}</span>
                </button>
                <button *ngIf="electron.isElectron" cdkMenuItem class="cg-menu-item" [routerLink]="['/settings/server']">
                  <app-icon>dns</app-icon>
                  <span>{{ 'settings.server' | translate }}</span>
                </button>

                <div class="cg-menu-sep"></div>

                <div class="cg-menu-label">{{ 'settings.language' | translate }}</div>
                <button cdkMenuItem class="cg-menu-item" *ngFor="let l of i18n.languages" (click)="i18n.setLang(l.code)">
                  <span class="lang-flag">{{ l.flag }}</span>
                  <span class="lang-label">{{ l.label }}</span>
                  <app-icon *ngIf="i18n.lang() === l.code" class="check">check</app-icon>
                </button>

                <div class="cg-menu-sep"></div>

                <div class="cg-menu-label">{{ 'settings.theme' | translate }}</div>
                <button cdkMenuItem class="cg-menu-item" (click)="$event.stopPropagation(); theme.toggle()">
                  <app-icon>{{ theme.isDark ? 'light_mode' : 'dark_mode' }}</app-icon>
                  <span>{{ (theme.isDark ? 'settings.theme.light' : 'settings.theme.dark') | translate }}</span>
                </button>

                <div class="cg-menu-sep"></div>

                <button cdkMenuItem class="cg-menu-item logout-item" (click)="auth.logout()">
                  <app-icon>logout</app-icon>
                  <span>{{ 'topbar.logout' | translate }}</span>
                </button>
              </div>
            </ng-template>
          </ng-container>
        </header>

        <main class="main-content">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
  `,
  styles: [`
    .user-menu-trigger {
      display: flex;
      align-items: center;
      gap: 5px;
      font-size: 12px;
      font-family: inherit;
      color: var(--cg-text-muted);
      background: none;
      border: none;
      cursor: pointer;
      padding: 4px 8px;
      border-radius: 6px;
      transition: background 0.12s, color 0.12s;

      &:hover { background: var(--cg-border); color: var(--cg-text); }

      .um-person { font-size: 15px; width: 15px; height: 15px; opacity: .7; }
      .um-name   { font-weight: 500; }
      .um-totp   { font-size: 13px; width: 13px; height: 13px; color: #4ade80; }
      .um-chevron { font-size: 16px; width: 16px; height: 16px; opacity: 0.5; }
    }
    .admin-badge {
      background: var(--cg-accent-soft);
      color: var(--cg-accent);
      font-size: 10px;
      font-weight: 700;
      padding: 1px 6px;
      border-radius: 10px;
      letter-spacing: 0.3px;
    }
    .sidebar-toggle-btn {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 36px;
      background: none;
      border: none;
      border-top: 1px solid var(--cg-sidebar-border);
      cursor: pointer;
      color: var(--cg-sidebar-fg-muted);
      transition: background 0.12s, color 0.12s;
      flex-shrink: 0;
&:hover { background: var(--cg-sidebar-hover); color: var(--cg-sidebar-active-fg); }
    }
  `],
})
export class ShellComponent {
  collapsed = signal(localStorage.getItem('sidebar-collapsed') === '1');

  constructor(
    public theme: ThemeService,
    public auth: AuthService,
    public i18n: TranslationService,
    public electron: ElectronService,
  ) {}

  toggleSidebar(): void {
    this.collapsed.update(v => !v);
    localStorage.setItem('sidebar-collapsed', this.collapsed() ? '1' : '0');
  }
}
