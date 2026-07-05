import { ChangeDetectionStrategy, ChangeDetectorRef, Component, Inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DialogRef, DIALOG_DATA } from '@angular/cdk/dialog';
import { Observable } from 'rxjs';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { extractApiError } from '../utils/http-error.util';

/** Config for the shared name+description create dialog. `submit` carries the
 *  actual API call (e.g. createGroup/createProject) so this dialog stays generic. */
export interface EntityFormDialogData {
  titleKey: string;
  namePlaceholderKey: string;
  descPlaceholderKey: string;
  createErrorKey: string;
  submit: (body: { name: string; description?: string }) => Observable<unknown>;
}

@Component({
  selector: 'app-entity-form-dialog',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, TranslatePipe],
  template: `
    <div class="cg-dialog">
      <h2 class="cg-dialog-title">{{ data.titleKey | translate }}</h2>
      <!-- Width comes from the dialog.open() config; a min-width here would
           overflow the pane (fields poking past the right padding). -->
      <div class="cg-dialog-content" style="display:flex;flex-direction:column;gap:14px;">
        <div class="cg-field">
          <label class="cg-label">{{ 'common.title' | translate }}</label>
          <input class="cg-input" [(ngModel)]="name" [placeholder]="data.namePlaceholderKey | translate" autofocus />
        </div>
        <div class="cg-field">
          <label class="cg-label">{{ 'common.descriptionOptional' | translate }}</label>
          <textarea class="cg-textarea" [(ngModel)]="description" rows="3"
            [placeholder]="data.descPlaceholderKey | translate"></textarea>
        </div>
        <p *ngIf="error" style="color:#e5484d;font-size:13px;margin:0;">{{ error }}</p>
      </div>
      <div class="cg-dialog-actions">
        <button class="cg-btn" (click)="dialogRef.close()">{{ 'common.cancel' | translate }}</button>
        <button class="cg-btn cg-btn-primary" (click)="save()" [disabled]="!name.trim() || saving">
          {{ (saving ? 'common.saving' : 'common.create') | translate }}
        </button>
      </div>
    </div>
  `,
})
export class EntityFormDialogComponent {
  name = '';
  description = '';
  saving = false;
  error = '';

  constructor(
    public dialogRef: DialogRef<unknown>,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
    @Inject(DIALOG_DATA) public data: EntityFormDialogData,
  ) {}

  save(): void {
    this.saving = true;
    const body = {
      name: this.name.trim(),
      ...(this.description.trim() && { description: this.description.trim() }),
    };
    this.data.submit(body).subscribe({
      next: (result) => this.dialogRef.close(result),
      error: (err) => {
        this.saving = false;
        this.error = extractApiError(err, this.i18n.t(this.data.createErrorKey));
        this.cdr.markForCheck();
      },
    });
  }
}
