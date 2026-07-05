import { ChangeDetectionStrategy, Component, Inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DialogRef, DIALOG_DATA } from '@angular/cdk/dialog';
import { IconComponent } from './icon.component';
import { TranslatePipe } from '../services/translate.pipe';

export interface DeleteConfirmData {
  name: string;
  kind: string;
}

@Component({
  selector: 'app-delete-confirm-dialog',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, IconComponent, TranslatePipe],
  template: `
    <div class="cg-dialog">
      <h2 class="cg-dialog-title">
        <app-icon style="color:#ef4444;">delete_forever</app-icon>
        {{ 'delete.title' | translate:{ kind: data.kind } }}
      </h2>
      <div class="cg-dialog-content" style="min-width:360px;">
        <p style="margin:0 0 6px;" [innerHTML]="'delete.warning' | translate"></p>
        <p style="margin:0 0 14px;font-size:13px;color:var(--cg-text-muted);">
          <code>{{ data.name }}</code>
        </p>
        <div class="cg-field">
          <label class="cg-label">{{ 'delete.confirmLabel' | translate }}</label>
          <input class="cg-input" [(ngModel)]="typed" [placeholder]="data.name" autofocus
                 (keydown.enter)="typed === data.name && confirm()" />
        </div>
      </div>
      <div class="cg-dialog-actions">
        <button class="cg-btn" (click)="dialogRef.close()">{{ 'common.cancel' | translate }}</button>
        <button class="cg-btn cg-btn-primary" [class.cg-btn-danger]="true"
                [disabled]="typed !== data.name" (click)="confirm()">
          <app-icon>delete</app-icon> {{ 'common.delete' | translate }}
        </button>
      </div>
    </div>
  `,
  styles: [`
    code { font-family: 'JetBrains Mono', monospace; background: rgba(0,0,0,.08); padding: 2px 7px; border-radius: 4px; font-size: 13px; }
    .cg-btn-danger { background: #ef4444; border-color: #ef4444; color: #fff; }
    .cg-btn-danger:hover:not(:disabled) { background: #dc2626; border-color: #dc2626; }
  `],
})
export class DeleteConfirmDialogComponent {
  typed = '';

  constructor(
    public dialogRef: DialogRef<boolean>,
    @Inject(DIALOG_DATA) public data: DeleteConfirmData,
  ) {}

  confirm(): void {
    this.dialogRef.close(true);
  }
}
