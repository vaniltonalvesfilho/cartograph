import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { AuthService } from '../services/auth.service';
import { TranslatePipe } from '../services/translate.pipe';

interface NavItem {
  route: string;
  icon: string;
  /** i18n key; unknown keys (e.g. 'GraphQL') fall back to themselves. */
  labelKey: string;
  exact?: boolean;
}

@Component({
  selector: 'app-sidebar',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, RouterLink, RouterLinkActive,
    IconComponent, TooltipDirective,
    TranslatePipe,
  ],
  template: `
    <nav class="sidebar-nav" [class.nav-collapsed]="collapsed">
      <a *ngFor="let item of mainItems" class="nav-item" [routerLink]="item.route"
         routerLinkActive="active" [routerLinkActiveOptions]="{ exact: !!item.exact }"
         [cgTooltip]="collapsed ? (item.labelKey | translate) : ''" cgTooltipPos="after">
        <app-icon>{{ item.icon }}</app-icon>
        <span *ngIf="!collapsed">{{ item.labelKey | translate }}</span>
      </a>
      <ng-container *ngIf="(auth.currentUser$ | async)?.isAdmin">
        <div *ngIf="!collapsed" class="nav-section-label">{{ 'sidebar.administration' | translate }}</div>
        <a *ngFor="let item of adminItems" class="nav-item" [routerLink]="item.route"
           routerLinkActive="active"
           [cgTooltip]="collapsed ? (item.labelKey | translate) : ''" cgTooltipPos="after">
          <app-icon>{{ item.icon }}</app-icon>
          <span *ngIf="!collapsed">{{ item.labelKey | translate }}</span>
        </a>
      </ng-container>
    </nav>
  `,
  styles: [`
    :host { display: flex; flex-direction: column; flex: 1; min-height: 0; }

    .sidebar-nav { padding: 8px; }

    .nav-section-label {
      font-size: 10px;
      font-weight: 600;
      letter-spacing: 0.7px;
      text-transform: uppercase;
      color: var(--cg-sidebar-fg-muted);
      padding: 10px 12px 4px 12px;
    }

    .nav-item {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 8px 10px;
      border-radius: 6px;
      text-decoration: none;
      font-size: 13.5px;
      font-weight: 500;
      color: var(--cg-sidebar-fg);
      transition: background 0.12s, color 0.12s;

      app-icon { font-size: 18px; width: 18px; height: 18px; opacity: 0.85; }

      &:hover { background: var(--cg-sidebar-hover); color: var(--cg-sidebar-active-fg); }
      &.active {
        background: var(--cg-sidebar-active-bg);
        color: var(--cg-sidebar-active-fg);
        app-icon { opacity: 1; color: var(--cg-accent); }
      }
    }

    .nav-collapsed .nav-item {
      justify-content: center;
      padding: 8px 0;
    }
  `],
})
export class SidebarComponent {
  @Input() collapsed = false;

  readonly mainItems: NavItem[] = [
    { route: '/', icon: 'dashboard', labelKey: 'sidebar.server', exact: true },
    { route: '/explore', icon: 'account_tree', labelKey: 'sidebar.explore' },
    { route: '/tasks', icon: 'grid_view', labelKey: 'sidebar.allJobs' },
    { route: '/monitor', icon: 'monitor_heart', labelKey: 'sidebar.monitoring' },
    { route: '/files', icon: 'folder', labelKey: 'files.title' },
  ];

  readonly adminItems: NavItem[] = [
    { route: '/admin/users', icon: 'manage_accounts', labelKey: 'sidebar.users' },
    { route: '/admin/data-sources', icon: 'storage', labelKey: 'dataSources.title' },
    { route: '/admin/smtp', icon: 'mail', labelKey: 'smtp.title' },
  ];

  constructor(public auth: AuthService) {}
}
