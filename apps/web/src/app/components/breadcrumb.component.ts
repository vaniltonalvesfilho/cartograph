import { ChangeDetectionStrategy, Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IconComponent } from './icon.component';
import { NavContextService } from '../services/nav-context.service';

@Component({
  selector: 'app-breadcrumb',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, RouterLink, IconComponent],
  template: `
    <nav class="breadcrumb" *ngIf="(ctx.crumbs | async) as crumbs">
      <a [routerLink]="['/']">Cartograph</a>
      <ng-container *ngFor="let c of crumbs">
        <app-icon class="crumb-sep">chevron_right</app-icon>
        <a *ngIf="c.link" [routerLink]="c.link">{{ c.label }}</a>
        <span *ngIf="!c.link" class="crumb-current">{{ c.label }}</span>
      </ng-container>
    </nav>
  `,
})
export class BreadcrumbComponent {
  constructor(public ctx: NavContextService) {}
}
