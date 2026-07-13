import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { Project } from '../models';
import { TranslationService } from '../services/translation.service';
import { TranslatePipe } from '../services/translate.pipe';
import { JobFormComponent, JobFormModel } from './job-form.component';
import { extractApiError } from '../utils/http-error.util';

const DEFAULT_DSL = `processFiles {
  step "readDirectory" {
    path "data/inbox"
  },
  step "filter" {
    extension "txt"
  },
  // use "outro-job-8iqX81Va",   // inclui os steps de outro job aqui
  step "transform" {
    operation "uppercase"
  },
  step "writeOutput" {
    path "data/outbox"
  },
}`;

@Component({
  selector: 'app-task-create',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective,
    TranslatePipe, JobFormComponent,
  ],
  template: `
    <div class="page-header">
      <app-icon class="page-icon">add_circle</app-icon>
      <div>
        <h2 class="page-title">{{ 'tasks.new' | translate }}</h2>
        <p class="page-subtitle">{{ 'taskCreate.subtitle' | translate }}</p>
      </div>
    </div>

    <app-job-form
      [model]="model" [projects]="projects" [steps]="steps"
      [saving]="saving" [error]="error" saveLabel="taskCreate.createBtn" [dslRows]="16"
      (nameChange)="onNameChange()" (save)="save()" (cancel)="cancel()">

      <div jobFormIdentifier class="cg-field">
        <label class="cg-label">
          {{ 'taskForm.identifier' | translate }}
          <app-icon class="hint-ic" [cgTooltip]="'taskForm.identifierTooltip' | translate">help_outline</app-icon>
        </label>
        <input class="cg-input" [(ngModel)]="identifier" (ngModelChange)="identifierTouched = true"
               [placeholder]="'taskForm.identifierPlaceholder' | translate" />
        <span class="field-hint">{{ 'taskForm.identifierHint' | translate }}</span>
      </div>
    </app-job-form>
  `,
  styles: [`
    .page-icon { font-size: 32px; color: var(--cg-accent); opacity: 0.9; }
    .hint-ic { font-size: 15px; color: var(--cg-text-muted); cursor: help; vertical-align: middle; }
    .field-hint { margin: -4px 0 8px; font-size: 12px; color: var(--cg-text-muted); }
  `],
})
export class TaskCreateComponent implements OnInit {
  model: JobFormModel = {
    name: '', description: '', dsl: DEFAULT_DSL, cron: '',
    releaseAt: null, archiveAt: null, projectId: null, agentTokenBudget: null,
  };
  identifier = '';
  identifierTouched = false;
  steps: string[] = [];
  projects: Project[] = [];
  saving = false;
  error = '';

  constructor(
    private api: ApiService,
    private route: ActivatedRoute,
    private router: Router,
    private nav: NavContextService,
    private i18n: TranslationService,
    private cdr: ChangeDetectorRef,
  ) {}

  ngOnInit(): void {
    this.nav.set([{ label: this.i18n.t('sidebar.allJobs'), link: ['/tasks'] }, { label: this.i18n.t('tasks.new') }]);
    this.api.availableSteps().subscribe(s => { this.steps = s; this.cdr.markForCheck(); });
    this.api.listProjects().subscribe(p => { this.projects = p; this.cdr.markForCheck(); });

    const qp = this.route.snapshot.queryParamMap.get('projectId');
    if (qp) this.model.projectId = Number(qp);
  }

  /** Auto-fill the identifier from the name until the user edits it directly. */
  onNameChange(): void {
    if (!this.identifierTouched) this.identifier = this.slug(this.model.name);
  }

  private slug(value: string): string {
    return value
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }

  save(): void {
    this.error = '';
    const identifier = this.slug(this.identifier);
    if (!identifier) {
      this.error = this.i18n.t('taskForm.identifierRequired');
      return;
    }
    this.identifier = identifier;
    this.saving = true;
    const m = this.model;
    const body: any = { name: m.name, identifier, dsl: m.dsl, projectId: m.projectId };
    if (m.description.trim()) body.description = m.description.trim();
    if (m.cron.trim()) body.cron = m.cron.trim();
    body.releaseAt = m.releaseAt;
    body.archiveAt = m.archiveAt;
    if (m.agentTokenBudget != null && m.agentTokenBudget !== ('' as any)) {
      body.agentTokenBudget = Number(m.agentTokenBudget);
    }

    this.api.createTask(body).subscribe({
      next: () => {
        if (m.projectId != null) this.router.navigate(['/projects', m.projectId]);
        else this.router.navigate(['/tasks']);
      },
      error: (err) => {
        this.saving = false;
        this.error = extractApiError(err, this.i18n.t('taskCreate.saveError'));
        this.cdr.markForCheck();
      },
    });
  }

  cancel(): void {
    this.router.navigate(['/tasks']);
  }
}
