import { ChangeDetectionStrategy, ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { forkJoin } from 'rxjs';
import { ApiService } from '../services/api.service';
import { NavContextService } from '../services/nav-context.service';
import { TaskDefinition, Project } from '../models';
import { MembersPanelComponent } from './members-panel.component';
import { CopyIdComponent } from './copy-id.component';
import { ExecutionHistoryComponent } from './execution-history.component';
import { TranslationService } from '../services/translation.service';
import { extractApiError } from '../utils/http-error.util';
import { TranslatePipe } from '../services/translate.pipe';
import { JobFormComponent, JobFormModel } from './job-form.component';

@Component({
  selector: 'app-task-edit',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule,
    MembersPanelComponent, ExecutionHistoryComponent, CopyIdComponent, TranslatePipe,
    JobFormComponent,
  ],
  template: `
    <app-job-form *ngIf="task"
      [model]="model" [projects]="projects" [steps]="steps"
      [saving]="saving" [error]="error" saveLabel="taskEdit.saveBtn" [dslRows]="14"
      (save)="save()" (cancel)="cancel()">

      <div jobFormHeader>
        <h2 class="card-title">{{ 'taskEdit.title' | translate }}</h2>
        <p class="card-sub">{{ task.name }}</p>
      </div>

      <div jobFormHeader *ngIf="task.code" class="use-snippet-row">
        <span class="field-label" style="margin: 0;">{{ 'taskEdit.jobId' | translate }}</span>
        <app-copy-id [value]="task.code"></app-copy-id>
        <span class="use-snippet-hint">{{ 'taskEdit.jobIdHint' | translate }}</span>
      </div>

      <div jobFormIdentifier class="cg-field" *ngIf="task.identifier">
        <label class="cg-label">{{ 'taskForm.identifier' | translate }}</label>
        <input class="cg-input" [value]="task.identifier" readonly disabled />
        <span class="field-hint">{{ 'taskForm.identifierImmutable' | translate }}</span>
      </div>
    </app-job-form>

    <app-members-panel *ngIf="task" subjectType="task" [subjectId]="task.id"></app-members-panel>

    <app-execution-history *ngIf="task" [taskId]="task.id"></app-execution-history>

    <div *ngIf="!task && !loading" style="padding: 32px; text-align: center; opacity: 0.5;">
      {{ 'taskEdit.notFound' | translate }}
    </div>
  `,
  styles: [`
    .card-title { margin: 0; font-size: 18px; font-weight: 700; color: var(--cg-text); }
    .card-sub { margin: 2px 0 0; font-size: 13px; color: var(--cg-text-muted); }
    .field-label {
      display: block;
      font-size: 12px;
      font-weight: 600;
      color: var(--cg-text-muted);
      margin: 4px 0 8px;
    }
    .field-hint { display:block; margin: -4px 0 8px; font-size: 12px; color: var(--cg-text-muted); }
    .use-snippet-row {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 16px;
    }
    .use-snippet-hint { font-size: 12px; color: var(--cg-text-muted); }
  `],
})
export class TaskEditComponent implements OnInit {
  task?: TaskDefinition;
  model: JobFormModel = {
    name: '', description: '', dsl: '', cron: '',
    releaseAt: null, archiveAt: null, projectId: null,
  };
  steps: string[] = [];
  projects: Project[] = [];
  saving = false;
  loading = true;
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
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.nav.set([{ label: this.i18n.t('sidebar.allJobs'), link: ['/tasks'] }, { label: this.i18n.t('taskEdit.title') }]);
    this.api.availableSteps().subscribe(s => { this.steps = s; this.cdr.markForCheck(); });
    forkJoin({
      projects: this.api.listProjects(),
      tasks: this.api.listTasks(),
    }).subscribe(({ projects, tasks }) => {
      this.loading = false;
      this.projects = projects;
      this.task = tasks.find(t => t.id === id);
      if (this.task) {
        this.model = {
          name: this.task.name,
          description: this.task.description ?? '',
          dsl: this.task.dsl,
          cron: this.task.cron ?? '',
          releaseAt: this.task.releaseAt ?? null,
          archiveAt: this.task.archiveAt ?? null,
          projectId: this.task.projectId ?? null,
        };
      }
      this.cdr.markForCheck();
    });
  }

  save(): void {
    this.error = '';
    this.saving = true;
    const m = this.model;
    const body: any = { name: m.name, description: m.description.trim() || null, dsl: m.dsl, projectId: m.projectId };
    body.cron = m.cron.trim() || null;
    body.releaseAt = m.releaseAt;
    body.archiveAt = m.archiveAt;

    this.api.updateTask(this.task!.id, body).subscribe({
      next: () => this.goBack(),
      error: (err) => {
        this.saving = false;
        this.error = extractApiError(err, this.i18n.t('taskEdit.saveError'));
        this.cdr.markForCheck();
      },
    });
  }

  cancel(): void {
    this.goBack();
  }

  private goBack(): void {
    if (this.model.projectId != null) this.router.navigate(['/projects', this.model.projectId]);
    else this.router.navigate(['/tasks']);
  }
}
