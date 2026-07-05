import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnChanges, Output, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CronHelperService } from '../services/cron-helper.service';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';

type Freq = 'none' | 'hourly' | 'daily' | 'weekly' | 'monthly' | 'advanced';

/**
 * Friendly recurrence builder that replaces the raw cron input. The user picks
 * a frequency (hourly / daily / weekly / monthly) and the period fields; the
 * component generates the cron expression and emits it via `cronChange`. An
 * "advanced" mode still exposes the raw cron for power users. Cron remains the
 * storage format consumed by the backend scheduler.
 */
@Component({
  selector: 'app-schedule-builder',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, TranslatePipe],
  template: `
    <div class="sched">
      <div class="cg-field" style="width:100%;">
        <label class="cg-label">{{ 'schedule.frequency' | translate }}</label>
        <select class="cg-select" [(ngModel)]="freq" (ngModelChange)="emit()">
          <option value="none">{{ 'schedule.none' | translate }}</option>
          <option value="hourly">{{ 'schedule.hourly' | translate }}</option>
          <option value="daily">{{ 'schedule.daily' | translate }}</option>
          <option value="weekly">{{ 'schedule.weekly' | translate }}</option>
          <option value="monthly">{{ 'schedule.monthly' | translate }}</option>
          <option value="advanced">{{ 'schedule.advanced' | translate }}</option>
        </select>
      </div>

      <!-- Hourly: minute -->
      <div class="cg-field" *ngIf="freq === 'hourly'" style="width:160px;">
        <label class="cg-label">{{ 'schedule.atMinute' | translate }}</label>
        <input class="cg-input" type="number" min="0" max="59" [(ngModel)]="minute" (ngModelChange)="emit()" />
      </div>

      <!-- Daily/Weekly/Monthly: time -->
      <div class="cg-field" *ngIf="freq === 'daily' || freq === 'weekly' || freq === 'monthly'" style="width:160px;">
        <label class="cg-label">{{ 'schedule.atTime' | translate }}</label>
        <input class="cg-input" type="time" [(ngModel)]="time" (ngModelChange)="emit()" />
      </div>

      <!-- Weekly: weekdays as toggle chips -->
      <div class="cg-field" *ngIf="freq === 'weekly'" style="flex-basis:100%;">
        <label class="cg-label">{{ 'schedule.onDays' | translate }}</label>
        <div class="dow-chips">
          <button type="button" *ngFor="let d of weekdays"
                  class="dow-chip" [class.on]="dows.includes(d.value)"
                  (click)="toggleDow(d.value)">{{ d.key | translate }}</button>
        </div>
      </div>

      <!-- Monthly: day of month -->
      <div class="cg-field" *ngIf="freq === 'monthly'" style="width:160px;">
        <label class="cg-label">{{ 'schedule.dayOfMonth' | translate }}</label>
        <input class="cg-input" type="number" min="1" max="31" [(ngModel)]="dayOfMonth" (ngModelChange)="emit()" />
      </div>

      <!-- Advanced: raw cron -->
      <div class="cg-field" *ngIf="freq === 'advanced'" style="width:100%;">
        <label class="cg-label">{{ 'schedule.cronExpression' | translate }}</label>
        <input class="cg-input" [(ngModel)]="raw" (ngModelChange)="emit()" placeholder="ex: 0 9 * * 1-5" />
      </div>

      <p class="sched-summary" *ngIf="freq !== 'none'">
        <span *ngIf="description">{{ description }}</span>
        <code class="sched-cron">{{ build() || '—' }}</code>
      </p>
    </div>
  `,
  styles: [`
    .sched { display: flex; flex-wrap: wrap; gap: 12px; align-items: flex-start; }
    .dow-chips { display: flex; flex-wrap: wrap; gap: 6px; }
    .dow-chip {
      font: inherit; font-size: 12.5px; font-weight: 500;
      padding: 6px 12px; border-radius: 999px; cursor: pointer;
      border: 1px solid var(--cg-border-strong);
      background: var(--cg-surface); color: var(--cg-text-muted);
      transition: all .12s;
    }
    .dow-chip:hover { border-color: var(--cg-accent); }
    .dow-chip.on {
      background: var(--cg-accent-soft); border-color: var(--cg-accent); color: var(--cg-accent);
    }
    .sched-summary {
      flex-basis: 100%;
      margin: 0 0 4px;
      font-size: 13px;
      color: var(--cg-text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .sched-cron {
      background: rgba(0,0,0,.08);
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 12px;
      font-family: 'JetBrains Mono', monospace;
    }
  `],
})
export class ScheduleBuilderComponent implements OnChanges {
  @Input() cron = '';
  @Output() cronChange = new EventEmitter<string>();

  freq: Freq = 'none';
  minute = 0;
  time = '09:00';
  dows: number[] = [1, 2, 3, 4, 5];
  dayOfMonth = 1;
  raw = '';

  // cron day-of-week is 0=Sunday..6=Saturday; list Mon-first for familiarity.
  readonly weekdays = [
    { value: 1, key: 'schedule.dow.1' },
    { value: 2, key: 'schedule.dow.2' },
    { value: 3, key: 'schedule.dow.3' },
    { value: 4, key: 'schedule.dow.4' },
    { value: 5, key: 'schedule.dow.5' },
    { value: 6, key: 'schedule.dow.6' },
    { value: 0, key: 'schedule.dow.0' },
  ];

  constructor(private cronHelper: CronHelperService, public i18n: TranslationService) {}

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['cron']) this.parse(this.cron ?? '');
  }

  get description(): string {
    const expr = this.build();
    return expr ? this.cronHelper.describe(expr) : '';
  }

  build(): string {
    switch (this.freq) {
      case 'none': return '';
      case 'hourly': return `${this.clamp(this.minute, 0, 59)} * * * *`;
      case 'daily': return `${this.tMin} ${this.tHour} * * *`;
      case 'weekly': {
        const days = (this.dows.length ? [...this.dows].sort((a, b) => a - b) : [1]).join(',');
        return `${this.tMin} ${this.tHour} * * ${days}`;
      }
      case 'monthly': return `${this.tMin} ${this.tHour} ${this.clamp(this.dayOfMonth, 1, 31)} * *`;
      case 'advanced': return this.raw.trim();
    }
  }

  emit(): void { this.cronChange.emit(this.build()); }

  toggleDow(v: number): void {
    this.dows = this.dows.includes(v) ? this.dows.filter(d => d !== v) : [...this.dows, v];
    this.emit();
  }

  private parse(expr: string): void {
    const e = (expr || '').trim();
    if (!e) { this.freq = 'none'; return; }
    const p = e.split(/\s+/);
    const num = (s: string) => /^\d+$/.test(s);
    if (p.length !== 5) { this.freq = 'advanced'; this.raw = e; return; }
    const [mi, h, dom, mon, dow] = p;

    if (num(mi) && h === '*' && dom === '*' && mon === '*' && dow === '*') {
      this.freq = 'hourly'; this.minute = +mi; return;
    }
    if (num(mi) && num(h) && dom === '*' && mon === '*' && dow === '*') {
      this.freq = 'daily'; this.setTime(+h, +mi); return;
    }
    if (num(mi) && num(h) && dom === '*' && mon === '*' && dow !== '*' && dow.split(',').every(num)) {
      this.freq = 'weekly'; this.setTime(+h, +mi); this.dows = dow.split(',').map(Number); return;
    }
    if (num(mi) && num(h) && num(dom) && mon === '*' && dow === '*') {
      this.freq = 'monthly'; this.setTime(+h, +mi); this.dayOfMonth = +dom; return;
    }
    this.freq = 'advanced'; this.raw = e;
  }

  private setTime(h: number, m: number): void {
    this.time = `${this.pad(h)}:${this.pad(m)}`;
  }

  private get tHour(): number { return this.clamp(+(this.time.split(':')[0] || 0), 0, 23); }
  private get tMin(): number { return this.clamp(+(this.time.split(':')[1] || 0), 0, 59); }

  private pad(n: number): string { return String(n).padStart(2, '0'); }
  private clamp(n: number, lo: number, hi: number): number {
    return Math.min(hi, Math.max(lo, Math.floor(n || 0)));
  }
}
