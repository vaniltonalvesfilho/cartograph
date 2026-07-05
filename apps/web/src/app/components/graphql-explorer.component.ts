import { ChangeDetectionStrategy, ChangeDetectorRef, Component, ElementRef, HostListener, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { CdkMenu, CdkMenuItem, CdkMenuTrigger } from '@angular/cdk/menu';
import { TranslatePipe } from '../services/translate.pipe';
import { TranslationService } from '../services/translation.service';
import { environment } from '../../environments/environment';

const GRAPHQL_URL = environment.graphqlHttp;
const TOKEN_KEY = 'cartograph-token';

interface Example {
  label: string;
  query: string;
  variables?: string;
}

const EXAMPLES: Example[] = [
  {
    label: 'List groups',
    query: `query {
  groups {
    id
    name
    parentId
    description
  }
}`,
  },
  {
    label: 'List projects',
    query: `query {
  projects {
    id
    name
    groupId
    description
  }
}`,
  },
  {
    label: 'Projects of a group',
    query: `query ProjectsByGroup($groupId: ID!) {
  projects(groupId: $groupId) {
    id
    name
    description
  }
}`,
    variables: `{\n  "groupId": "1"\n}`,
  },
  {
    label: 'List jobs',
    query: `query {
  tasks {
    id
    name
    code
    cron
    projectId
    createdAt
  }
}`,
  },
  {
    label: 'Jobs of a project',
    query: `query JobsByProject($projectId: ID!) {
  tasks(projectId: $projectId) {
    id
    name
    code
    cron
    dsl
  }
}`,
    variables: `{\n  "projectId": "1"\n}`,
  },
  {
    label: 'Job by ID',
    query: `query GetJob($id: ID!) {
  task(id: $id) {
    id
    name
    code
    dsl
    cron
    description
    releaseAt
    archiveAt
    createdAt
  }
}`,
    variables: `{\n  "id": "1"\n}`,
  },
  {
    label: 'Recent executions',
    query: `query {
  executions(limit: 20) {
    id
    taskName
    status
    trigger
    createdAt
    startedAt
    finishedAt
  }
}`,
  },
  {
    label: 'Executions of a job',
    query: `query ExecsByTask($taskId: ID!) {
  executions(taskId: $taskId, limit: 10) {
    id
    status
    trigger
    createdAt
    finishedAt
  }
}`,
    variables: `{\n  "taskId": "1"\n}`,
  },
  {
    label: 'Logs of an execution',
    query: `query GetLogs($executionId: ID!) {
  executionLogs(executionId: $executionId) {
    id
    level
    message
    insertedAt
  }
}`,
    variables: `{\n  "executionId": "1"\n}`,
  },
  {
    label: 'Dashboard metrics',
    query: `query {
  dashboardMetrics {
    totalTasks
    runningTasks
    failedToday
    successToday
  }
}`,
  },
  {
    label: 'Create group (mutation)',
    query: `mutation CreateGroup($name: String!) {
  createGroup(name: $name) {
    id
    name
  }
}`,
    variables: `{\n  "name": "My Group"\n}`,
  },
  {
    label: 'Introspection',
    query: `query {
  __schema {
    queryType { name }
    mutationType { name }
    types {
      name
      kind
    }
  }
}`,
  },
];

@Component({
  selector: 'app-graphql-explorer',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [
    CommonModule, FormsModule,
    IconComponent, TooltipDirective, CdkMenu, CdkMenuItem, CdkMenuTrigger,
    TranslatePipe,
  ],
  template: `
    <div class="gql-shell">
      <!-- Toolbar -->
      <div class="gql-toolbar">
        <div class="gql-title">
          <app-icon>hub</app-icon>
          <span>GraphQL Explorer</span>
        </div>
        <button class="cg-btn" [cdkMenuTriggerFor]="examplesMenu">
          <app-icon>auto_stories</app-icon>
          {{ 'gql.examples' | translate }}
        </button>
        <ng-template #examplesMenu>
          <div cdkMenu class="cg-menu" style="max-height:60vh;overflow:auto;">
            <button cdkMenuItem class="cg-menu-item" *ngFor="let ex of examples" (click)="loadExample(ex)">
              {{ ex.label }}
            </button>
          </div>
        </ng-template>
        <button class="cg-btn cg-btn-primary" (click)="run()" [disabled]="running"
                [cgTooltip]="'gql.runTip' | translate">
          <span *ngIf="running" class="cg-spinner" style="--d:16px;margin-right:6px;"></span>
          <app-icon *ngIf="!running">play_arrow</app-icon>
          {{ 'gql.run' | translate }}
        </button>
      </div>

      <!-- Main panels -->
      <div class="gql-panels">
        <!-- Left: editor + variables -->
        <div class="gql-left">
          <div class="panel-label">
            <app-icon>code</app-icon>
            {{ 'gql.query' | translate }}
            <span class="shortcut">Ctrl+Enter</span>
          </div>
          <div class="editor-wrap">
            <div class="line-nums" #lineNums>
              <div *ngFor="let n of lineNumbers">{{ n }}</div>
            </div>
            <textarea #queryEditor
              class="gql-editor"
              [(ngModel)]="query"
              (input)="onQueryInput()"
              (scroll)="syncScroll()"
              (keydown.control.enter)="run()"
              (keydown.tab)="onTab($any($event))"
              spellcheck="false"
              autocomplete="off"
              autocorrect="off"
              autocapitalize="off"
            ></textarea>
          </div>

          <div class="panel-label vars-label">
            <app-icon>data_object</app-icon>
            {{ 'gql.variables' | translate }}
            <span class="shortcut">JSON</span>
          </div>
          <textarea class="gql-vars"
            [(ngModel)]="variables"
            (keydown.tab)="onTab($any($event))"
            placeholder='{ "key": "value" }'
            spellcheck="false"
          ></textarea>
        </div>

        <!-- Right: response -->
        <div class="gql-right">
          <div class="panel-label">
            <app-icon>{{ error ? 'error_outline' : 'output' }}</app-icon>
            {{ 'gql.response' | translate }}
            <span *ngIf="responseTime" class="shortcut">{{ responseTime }}ms</span>
            <button *ngIf="responseJson" class="cg-icon-btn copy-btn"
                    (click)="copyResponse()" [cgTooltip]="'gql.copy' | translate">
              <app-icon>content_copy</app-icon>
            </button>
          </div>
          <div class="gql-response" [class.has-error]="error">
            <pre *ngIf="responseJson" class="response-pre" [innerHTML]="highlighted"></pre>
            <div *ngIf="!responseJson && !running" class="response-empty">
              <app-icon>play_circle_outline</app-icon>
              <p>{{ 'gql.runHint' | translate }}</p>
            </div>
            <div *ngIf="running" class="response-empty">
              <span class="cg-spinner" style="--d:32px;"></span>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    :host { display: flex; flex-direction: column; height: 100%; overflow: hidden; }

    .gql-shell {
      display: flex;
      flex-direction: column;
      height: 100%;
      overflow: hidden;
      gap: 0;
    }

    .gql-toolbar {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 10px 16px;
      border-bottom: 1px solid var(--cg-border);
      background: var(--cg-surface);
      flex-shrink: 0;
    }
    .gql-title {
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 15px;
      font-weight: 700;
      color: var(--cg-text);
      flex: 1;
      app-icon { color: #e10098; font-size: 20px; width: 20px; height: 20px; }
    }

    .gql-panels {
      display: flex;
      flex: 1;
      overflow: hidden;
      gap: 0;
    }

    .gql-left {
      display: flex;
      flex-direction: column;
      width: 50%;
      min-width: 0;
      border-right: 1px solid var(--cg-border);
      overflow: hidden;
    }

    .gql-right {
      display: flex;
      flex-direction: column;
      flex: 1;
      min-width: 0;
      overflow: hidden;
    }

    .panel-label {
      display: flex;
      align-items: center;
      gap: 6px;
      padding: 6px 12px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--cg-text-muted);
      background: var(--cg-content-bg);
      border-bottom: 1px solid var(--cg-border);
      flex-shrink: 0;
      app-icon { font-size: 14px; width: 14px; height: 14px; }
    }
    .vars-label { border-top: 1px solid var(--cg-border); }
    .shortcut {
      margin-left: auto;
      font-size: 10px;
      background: var(--cg-border);
      padding: 1px 6px;
      border-radius: 4px;
      font-weight: 500;
      letter-spacing: 0;
      text-transform: none;
    }
    .copy-btn {
      margin-left: auto;
      width: 24px; height: 24px;
      app-icon { font-size: 14px; width: 14px; height: 14px; }
    }

    .editor-wrap {
      display: flex;
      flex: 1;
      min-height: 0;
      overflow: hidden;
    }

    .line-nums {
      padding: 8px 0;
      min-width: 36px;
      text-align: right;
      padding-right: 8px;
      background: var(--cg-content-bg);
      color: var(--cg-text-muted);
      font-family: 'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace;
      font-size: 13px;
      line-height: 1.6;
      overflow: hidden;
      user-select: none;
      border-right: 1px solid var(--cg-border);
      flex-shrink: 0;
      div { height: 20.8px; }
    }

    .gql-editor {
      flex: 1;
      resize: none;
      border: none;
      outline: none;
      padding: 8px 12px;
      font-family: 'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace;
      font-size: 13px;
      line-height: 1.6;
      background: var(--cg-surface);
      color: var(--cg-text);
      overflow-y: auto;
      white-space: pre;
      overflow-x: auto;
    }

    .gql-vars {
      height: 120px;
      flex-shrink: 0;
      resize: none;
      border: none;
      outline: none;
      padding: 8px 12px;
      font-family: 'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace;
      font-size: 12px;
      line-height: 1.6;
      background: var(--cg-surface);
      color: var(--cg-text);
      border-top: 1px solid var(--cg-border);
    }

    .gql-response {
      flex: 1;
      overflow-y: auto;
      background: var(--cg-surface);
      &.has-error { background: rgba(239, 68, 68, 0.04); }
    }

    .response-pre {
      margin: 0;
      padding: 12px 16px;
      font-family: 'JetBrains Mono', 'SF Mono', Menlo, Consolas, monospace;
      font-size: 12.5px;
      line-height: 1.6;
      color: var(--cg-text);
      white-space: pre;
      overflow-x: auto;

      .json-key    { color: #7dd3fc; }
      .json-str    { color: #86efac; }
      .json-num    { color: #fbbf24; }
      .json-bool   { color: #c084fc; }
      .json-null   { color: #94a3b8; }
      .json-err    { color: #f87171; }
    }

    html:not(.dark-theme) .response-pre {
      .json-key  { color: #0369a1; }
      .json-str  { color: #15803d; }
      .json-num  { color: #b45309; }
      .json-bool { color: #7c3aed; }
      .json-null { color: #6b7280; }
      .json-err  { color: #dc2626; }
    }

    .response-empty {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      height: 100%;
      color: var(--cg-text-muted);
      gap: 12px;
      app-icon { font-size: 40px; width: 40px; height: 40px; opacity: 0.3; }
      p { font-size: 13px; margin: 0; }
    }
  `],
})
export class GraphqlExplorerComponent {
  @ViewChild('queryEditor') queryEditorRef!: ElementRef<HTMLTextAreaElement>;
  @ViewChild('lineNums') lineNumsRef!: ElementRef<HTMLDivElement>;

  examples = EXAMPLES;
  query = `query {\n  groups {\n    id\n    name\n    description\n  }\n}`;
  variables = '';
  responseJson = '';
  highlighted = '';
  error = false;
  running = false;
  responseTime: number | null = null;
  lineNumbers: number[] = [];

  constructor(private i18n: TranslationService, private cdr: ChangeDetectorRef) {
    this.updateLineNumbers();
  }

  loadExample(ex: Example): void {
    this.query = ex.query;
    this.variables = ex.variables ?? '';
    this.responseJson = '';
    this.highlighted = '';
    this.responseTime = null;
    this.error = false;
    this.updateLineNumbers();
  }

  onQueryInput(): void {
    this.updateLineNumbers();
  }

  onTab(e: KeyboardEvent): void {
    e.preventDefault();
    const el = e.target as HTMLTextAreaElement;
    const start = el.selectionStart;
    el.value = el.value.slice(0, start) + '  ' + el.value.slice(el.selectionEnd);
    el.selectionStart = el.selectionEnd = start + 2;
    if (el === this.queryEditorRef?.nativeElement) {
      this.query = el.value;
      this.updateLineNumbers();
    } else {
      this.variables = el.value;
    }
  }

  syncScroll(): void {
    if (this.queryEditorRef && this.lineNumsRef) {
      this.lineNumsRef.nativeElement.scrollTop = this.queryEditorRef.nativeElement.scrollTop;
    }
  }

  @HostListener('window:keydown', ['$event'])
  onGlobalKey(e: KeyboardEvent): void {
    if (e.ctrlKey && e.key === 'Enter') { e.preventDefault(); this.run(); }
  }

  async run(): Promise<void> {
    if (this.running) return;
    const q = this.query.trim();
    if (!q) return;

    let vars: Record<string, unknown> = {};
    if (this.variables.trim()) {
      try { vars = JSON.parse(this.variables); }
      catch { this.showError('Variables: invalid JSON'); return; }
    }

    this.running = true;
    this.responseJson = '';
    this.highlighted = '';
    this.error = false;
    const t0 = performance.now();

    try {
      const token = localStorage.getItem(TOKEN_KEY);
      const res = await fetch(GRAPHQL_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ query: q, variables: vars }),
      });
      const json = await res.json();
      this.responseTime = Math.round(performance.now() - t0);
      this.responseJson = JSON.stringify(json, null, 2);
      this.error = !!json.errors;
      this.highlighted = this.highlightJson(this.responseJson, !!json.errors);
    } catch (err: unknown) {
      this.responseTime = Math.round(performance.now() - t0);
      const msg = err instanceof Error ? err.message : String(err);
      this.showError(msg);
    } finally {
      this.running = false;
      this.cdr.markForCheck();
    }
  }

  copyResponse(): void {
    navigator.clipboard.writeText(this.responseJson);
  }

  private showError(msg: string): void {
    this.error = true;
    this.responseJson = msg;
    this.highlighted = `<span class="json-err">${this.escape(msg)}</span>`;
    this.running = false;
    this.cdr.markForCheck();
  }

  private updateLineNumbers(): void {
    const lines = (this.query.match(/\n/g) ?? []).length + 1;
    this.lineNumbers = Array.from({ length: lines }, (_, i) => i + 1);
  }

  private highlightJson(json: string, hasErrors: boolean): string {
    const escaped = this.escape(json);
    return escaped.replace(
      /("(?:[^"\\]|\\.)*")\s*:|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(\btrue\b|\bfalse\b)|(\bnull\b)/g,
      (_, key, str, num, bool, nil) => {
        if (key) return `<span class="json-key">${key}</span>:`;
        if (str) return `<span class="${hasErrors && str.includes('error') ? 'json-err' : 'json-str'}">${str}</span>`;
        if (num) return `<span class="json-num">${num}</span>`;
        if (bool) return `<span class="json-bool">${bool}</span>`;
        if (nil) return `<span class="json-null">${nil}</span>`;
        return _;
      },
    );
  }

  private escape(s: string): string {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
