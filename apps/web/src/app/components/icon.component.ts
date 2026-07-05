import { Component, ChangeDetectionStrategy } from '@angular/core';

/**
 * Lightweight icon that renders a Material Icons font ligature without any
 * @angular/material dependency. Usage: <app-icon>settings</app-icon>.
 * Size follows font-size (set on the host or a parent), like the old mat-icon.
 */
@Component({
  selector: 'app-icon',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `<i class="material-icons" aria-hidden="true"><ng-content></ng-content></i>`,
  styles: [`
    :host { display: inline-flex; align-items: center; justify-content: center; font-size: 20px; line-height: 1; }
    i {
      font-family: 'Material Icons';
      font-size: inherit;
      width: 1em;
      height: 1em;
      font-style: normal;
      font-weight: normal;
      letter-spacing: normal;
      text-transform: none;
      white-space: nowrap;
      direction: ltr;
      -webkit-font-feature-settings: 'liga';
      -webkit-font-smoothing: antialiased;
    }
  `],
})
export class IconComponent {}
