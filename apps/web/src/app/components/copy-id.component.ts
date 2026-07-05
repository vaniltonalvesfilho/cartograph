import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslatePipe } from '../services/translate.pipe';

/**
 * Small reusable "copy id" chip. Shows a value in a monospaced font with a
 * copy button. On copy it gives visual feedback (check icon) and a tooltip.
 *
 *   <app-copy-id [value]="task.code"></app-copy-id>
 *   <app-copy-id [value]="task.code" [label]="'taskEdit.jobId' | translate"></app-copy-id>
 */
@Component({
  selector: 'app-copy-id',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, TooltipDirective, TranslatePipe],
  template: `
    <span class="copy-id" *ngIf="value">
      <span *ngIf="label" class="copy-id-label">{{ label }}</span>
      <code class="copy-id-value">{{ value }}</code>
      <button class="cg-icon-btn"
              type="button"
              class="copy-id-btn"
              (click)="copy()"
              [cgTooltip]="(copied ? 'copyId.copied' : 'copyId.copy') | translate"
              [attr.aria-label]="'copyId.copy' | translate">
        <app-icon>{{ copied ? 'check' : 'content_copy' }}</app-icon>
      </button>
    </span>
  `,
  styles: [`
    .copy-id {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      max-width: 100%;
      padding: 2px 2px 2px 8px;
      border-radius: 8px;
      background: var(--cg-surface-2, rgba(127, 127, 127, 0.12));
      border: 1px solid var(--cg-border, rgba(127, 127, 127, 0.2));
    }
    .copy-id-label {
      font-size: 11px;
      font-weight: 600;
      color: var(--cg-text-muted);
      text-transform: uppercase;
      letter-spacing: 0.4px;
    }
    .copy-id-value {
      font-family: ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, monospace;
      font-size: 12px;
      line-height: 1.3;
      color: var(--cg-text, inherit);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .copy-id-btn {
      width: 26px;
      height: 26px;
      line-height: 26px;
      flex: 0 0 auto;
    }
    .copy-id-btn app-icon {
      font-size: 16px;
      width: 16px;
      height: 16px;
      line-height: 16px;
    }
  `],
})
export class CopyIdComponent {
  @Input() value = '';
  @Input() label?: string;

  copied = false;
  private resetTimer?: ReturnType<typeof setTimeout>;

  constructor(private cdr: ChangeDetectorRef) {}

  copy(): void {
    if (!this.value) return;
    const done = () => {
      this.copied = true;
      this.cdr.markForCheck();
      clearTimeout(this.resetTimer);
      this.resetTimer = setTimeout(() => {
        this.copied = false;
        this.cdr.markForCheck();
      }, 1500);
    };

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(this.value).then(done).catch(() => this.fallbackCopy(done));
    } else {
      this.fallbackCopy(done);
    }
  }

  private fallbackCopy(done: () => void): void {
    const el = document.createElement('textarea');
    el.value = this.value;
    el.style.position = 'fixed';
    el.style.opacity = '0';
    document.body.appendChild(el);
    el.select();
    try { document.execCommand('copy'); done(); } catch { /* ignore */ }
    document.body.removeChild(el);
  }
}
