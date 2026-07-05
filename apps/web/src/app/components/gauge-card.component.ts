import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

/**
 * A circular gauge card: an SVG ring driven by `percent`, a centered value/unit,
 * and slots for a legend and a footer. Pass `innerPercent` to render a second
 * inner ring (used by the CPU gauge for the BEAM share). The ring colour follows
 * the value's severity (ok / warn / danger) via `:host` classes.
 */
@Component({
  selector: 'app-gauge-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  host: {
    class: 'gauge-card',
    '[class.ok]': "state === 'ok'",
    '[class.warn]': "state === 'warn'",
    '[class.danger]': "state === 'danger'",
    '[class.cpu-card]': 'innerPercent != null',
  },
  template: `
    <div class="gauge-ring">
      <svg viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="42" class="ring-bg"/>
        <circle cx="50" cy="50" r="42" class="ring-fg" [style.strokeDashoffset]="ringOffset(percent)"/>
        <ng-container *ngIf="innerPercent != null">
          <circle cx="50" cy="50" r="30" class="ring-bg ring-inner"/>
          <circle cx="50" cy="50" r="30" class="ring-fg ring-inner-fg" [style.strokeDashoffset]="ringOffsetInner(innerPercent)"/>
        </ng-container>
      </svg>
      <div class="gauge-center">
        <span class="gauge-value">{{ percent | number:'1.0-0' }}%</span>
        <span class="gauge-unit">{{ unit }}</span>
      </div>
    </div>
    <ng-content select="[gaugeLegend]"></ng-content>
    <ng-content select="[gaugeFooter]"></ng-content>
  `,
  styles: [`
    :host {
      flex: 1;
      min-width: 160px;
      background: var(--cg-surface);
      border: 1px solid var(--cg-border);
      border-radius: 10px;
      padding: 20px 16px 14px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 12px;
    }
    :host(.cpu-card) { gap: 10px; }
    .gauge-ring {
      position: relative;
      width: 110px;
      height: 110px;
    }
    .gauge-ring svg { width: 100%; height: 100%; transform: rotate(-90deg); }
    .ring-bg { fill: none; stroke: var(--cg-border); stroke-width: 9; }
    .ring-inner { stroke-width: 7; }
    .ring-fg {
      fill: none;
      stroke-width: 9;
      stroke-linecap: round;
      stroke-dasharray: 263.9;
      transition: stroke-dashoffset 0.5s ease, stroke 0.4s;
    }
    .ring-inner-fg {
      fill: none;
      stroke-width: 7;
      stroke-linecap: round;
      stroke-dasharray: 188.5;
      stroke: #60a5fa;
      transition: stroke-dashoffset 0.5s ease;
    }
    :host(.ok) .ring-fg     { stroke: #34d399; }
    :host(.warn) .ring-fg   { stroke: #fbbf24; }
    :host(.danger) .ring-fg { stroke: #f87171; }
    /* inner BEAM arc stays blue regardless of the outer status colour */
    :host(.ok) .ring-inner-fg,
    :host(.warn) .ring-inner-fg,
    :host(.danger) .ring-inner-fg { stroke: #60a5fa; }
    .gauge-center {
      position: absolute;
      inset: 0;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 1px;
    }
    .gauge-value { font-size: 22px; font-weight: 700; color: var(--cg-text); line-height: 1; }
    .gauge-unit  { font-size: 11px; color: var(--cg-text-muted); font-weight: 500; }
  `],
})
export class GaugeCardComponent {
  @Input({ required: true }) percent = 0;
  @Input() unit = '';
  @Input() innerPercent: number | null = null;

  get state(): 'ok' | 'warn' | 'danger' {
    if (this.percent >= 85) return 'danger';
    if (this.percent >= 60) return 'warn';
    return 'ok';
  }

  ringOffset(pct: number): number {
    return 263.9 * (1 - Math.min(pct, 100) / 100);
  }

  ringOffsetInner(pct: number): number {
    return 188.5 * (1 - Math.min(pct, 100) / 100);
  }
}
