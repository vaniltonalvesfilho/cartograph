import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { IconComponent } from './icon.component';

@Component({
  selector: 'app-metric-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [IconComponent],
  template: `
    <div class="metric-card">
      <div class="metric-top">
        <span class="metric-label">{{ label }}</span>
        <app-icon class="metric-icon" [style.color]="color">{{ icon }}</app-icon>
      </div>
      <div class="metric-value">{{ value }}</div>
    </div>
  `,
})
export class MetricCardComponent {
  @Input() label = '';
  @Input() value: string | number = 0;
  @Input() icon = 'info';
  @Input() color = 'inherit';
}
