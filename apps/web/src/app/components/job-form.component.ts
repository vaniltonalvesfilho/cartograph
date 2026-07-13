import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { Project } from '../models';
import { ScheduleBuilderComponent } from './schedule-builder.component';
import { ReleaseDatePickerComponent } from './release-date-picker.component';
import { TranslatePipe } from '../services/translate.pipe';
import { DslEditorComponent } from './dsl-editor.component';
import { JobCanvasComponent } from './job-canvas.component';

/** Fields shared by the create and edit job forms. The `identifier` is handled
 *  per-parent (editable on create, read-only on edit) via the identifier slot. */
export interface JobFormModel {
  name: string;
  description: string;
  dsl: string;
  cron: string;
  releaseAt: string | null;
  archiveAt: string | null;
  projectId: number | null;
  agentTokenBudget: number | null;
}

@Component({
  selector: 'app-job-form',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent,
    TranslatePipe, ScheduleBuilderComponent, ReleaseDatePickerComponent,
    DslEditorComponent, JobCanvasComponent,
  ],
  template: `
    <div class="cg-panel cg-panel-body padded form-stack">
      <ng-content select="[jobFormHeader]"></ng-content>

      <div class="cg-field">
        <label class="cg-label">{{ 'common.title' | translate }}</label>
        <input class="cg-input" [(ngModel)]="model.name" (ngModelChange)="nameChange.emit(model.name)"
               [placeholder]="'taskForm.namePlaceholder' | translate" />
      </div>

      <ng-content select="[jobFormIdentifier]"></ng-content>

      <div class="cg-field">
        <label class="cg-label">{{ 'common.descriptionOptional' | translate }}</label>
        <textarea class="cg-textarea" [(ngModel)]="model.description" rows="2"
          [placeholder]="'taskForm.descPlaceholder' | translate"></textarea>
      </div>

      <div class="dsl-toggle">
        <button class="cg-tab" [class.active]="view === 'dsl'" (click)="view = 'dsl'">
          <app-icon>code</app-icon> Editor DSL
        </button>
        <button class="cg-tab" [class.active]="view === 'canvas'" (click)="view = 'canvas'">
          <app-icon>schema</app-icon> Canvas Visual
          <span class="beta-badge">beta</span>
        </button>
      </div>
      <app-dsl-editor *ngIf="view === 'dsl'" [(ngModel)]="model.dsl" [rows]="dslRows"></app-dsl-editor>
      <app-job-canvas *ngIf="view === 'canvas'" [dsl]="model.dsl" (dslChange)="model.dsl = $event"></app-job-canvas>
      <p class="field-hint" [innerHTML]="'taskForm.dslHint' | translate:{ steps: steps.join(', ') }"></p>

      <label class="field-label">{{ 'taskForm.schedule' | translate }}</label>
      <app-schedule-builder [cron]="model.cron" (cronChange)="model.cron = $event"></app-schedule-builder>

      <label class="field-label" style="margin-top: 8px;">{{ 'taskForm.releaseLabel' | translate }}</label>
      <app-release-date-picker [(value)]="model.releaseAt"></app-release-date-picker>
      <p class="field-hint">{{ 'taskForm.releaseHint' | translate }}</p>

      <label class="field-label" style="margin-top: 8px;">{{ 'taskForm.archiveLabel' | translate }}</label>
      <app-release-date-picker [(value)]="model.archiveAt"></app-release-date-picker>
      <p class="field-hint">{{ 'taskForm.archiveHint' | translate }}</p>

      <div class="cg-field" style="margin-top: 8px;">
        <label class="cg-label">{{ 'agent.budgetLabel' | translate }}</label>
        <input class="cg-input" type="number" min="0" step="1000" [(ngModel)]="model.agentTokenBudget"
               [placeholder]="'agent.budgetPlaceholder' | translate" style="max-width: 240px;" />
        <span class="field-hint">{{ 'agent.budgetHint' | translate }}</span>
      </div>

      <div class="cg-field" style="margin-top: 8px;">
        <label class="cg-label">{{ 'taskForm.project' | translate }}</label>
        <select class="cg-select" [(ngModel)]="model.projectId">
          <option [ngValue]="null">{{ 'taskForm.noProject' | translate }}</option>
          <option *ngFor="let p of projects" [ngValue]="p.id">{{ p.name }}</option>
        </select>
      </div>

      <p *ngIf="error" style="color:#e5484d; font-size: 13px; margin: 8px 0 0;">
        {{ error }}
      </p>

      <div style="margin-top: 16px; display:flex; gap:8px;">
        <button class="cg-btn cg-btn-primary" (click)="save.emit()" [disabled]="saving">
          <app-icon>save</app-icon>
          {{ (saving ? 'common.saving' : saveLabel) | translate }}
        </button>
        <button class="cg-btn" (click)="cancel.emit()">{{ 'common.cancel' | translate }}</button>
      </div>
    </div>
  `,
  styles: [`
    .form-stack { display: flex; flex-direction: column; gap: 14px; }
    .field-label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: var(--cg-text-muted);
      margin: 4px 0 8px;
    }
    .field-hint { display:block; margin: -4px 0 8px; font-size: 12px; color: var(--cg-text-muted); }
    .dsl-toggle { display: flex; gap: 4px; margin-bottom: 4px; }
    .beta-badge {
      font-size: 9px; font-weight: 700; padding: 1px 5px; border-radius: 10px;
      background: var(--cg-accent-soft); color: var(--cg-accent);
      text-transform: uppercase; letter-spacing: 0.3px;
    }
  `],
})
export class JobFormComponent {
  @Input({ required: true }) model!: JobFormModel;
  @Input() projects: Project[] = [];
  @Input() steps: string[] = [];
  @Input() saving = false;
  @Input() error = '';
  @Input() saveLabel = 'common.save';
  @Input() dslRows = 16;

  @Output() save = new EventEmitter<void>();
  @Output() cancel = new EventEmitter<void>();
  @Output() nameChange = new EventEmitter<string>();

  view: 'dsl' | 'canvas' = 'dsl';
}
