import { ChangeDetectionStrategy, Component, EventEmitter, Input, OnChanges, Output, SimpleChanges } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslatePipe } from '../services/translate.pipe';

/**
 * Release date picker: a native date input for the day plus a time field.
 * Bridges the two controls to a single ISO 8601 UTC string via two-way
 * `[(value)]`. Empty (no date) means "no release gate".
 */
@Component({
  selector: 'app-release-date-picker',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, IconComponent, TooltipDirective, TranslatePipe],
  template: `
    <div class="rel">
      <div class="cg-field rel-date">
        <label class="cg-label">{{ 'release.date' | translate }}</label>
        <input class="cg-input" type="date" [(ngModel)]="dateStr" (ngModelChange)="emit()" />
      </div>

      <div class="cg-field rel-time">
        <label class="cg-label">{{ 'release.time' | translate }}</label>
        <input class="cg-input" type="time" [(ngModel)]="time" (ngModelChange)="emit()" [disabled]="!dateStr" />
      </div>

      <button *ngIf="dateStr" class="cg-icon-btn rel-clear" type="button"
              [cgTooltip]="'taskForm.releaseClear' | translate" (click)="clear()">
        <app-icon>clear</app-icon>
      </button>
    </div>
  `,
  styles: [`
    .rel { display: flex; gap: 12px; align-items: flex-end; flex-wrap: wrap; }
    .rel-date { width: 180px; }
    .rel-time { width: 130px; }
    .rel-clear { align-self: flex-end; margin-bottom: 1px; }
  `],
})
export class ReleaseDatePickerComponent implements OnChanges {
  @Input() value: string | null = null;
  @Output() valueChange = new EventEmitter<string | null>();

  dateStr = '';
  time = '09:00';

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['value']) this.decompose(this.value);
  }

  emit(): void {
    this.valueChange.emit(this.compose());
  }

  clear(): void {
    this.dateStr = '';
    this.valueChange.emit(null);
  }

  private compose(): string | null {
    if (!this.dateStr) return null;
    const [h, m] = (this.time || '00:00').split(':').map(Number);
    const d = new Date(this.dateStr);
    d.setHours(h || 0, m || 0, 0, 0);
    return d.toISOString();
  }

  private decompose(iso: string | null): void {
    if (!iso) { this.dateStr = ''; this.time = '09:00'; return; }
    const d = new Date(iso);
    if (isNaN(d.getTime())) { this.dateStr = ''; return; }
    this.dateStr = d.toISOString().slice(0, 10);
    this.time = `${this.pad(d.getHours())}:${this.pad(d.getMinutes())}`;
  }

  private pad(n: number): string { return String(n).padStart(2, '0'); }
}
