import { Injectable } from '@angular/core';
import { Apollo } from 'apollo-angular';
import { Observable, map } from 'rxjs';
import * as Q from '../graphql/queries';
import { AbsintheSocketService } from './absinthe-socket.service';
import {
  DashboardMetrics,
  GqlExecutionDetail,
  GqlExecutionLog,
  GqlExecutionStatus,
  GqlStepExecution,
  GqlGroup,
  GqlProject,
  GqlTask,
  GqlExecution,
  RunResult,
} from '../graphql/types';

@Injectable({ providedIn: 'root' })
export class GraphQLService {
  constructor(private apollo: Apollo, private absinthe: AbsintheSocketService) {}

  // ── Queries ────────────────────────────────────────────────────────────────

  dashboardMetrics(): Observable<DashboardMetrics> {
    return this.apollo
      .watchQuery<{ dashboardMetrics: DashboardMetrics }>({ query: Q.DASHBOARD_METRICS, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data.dashboardMetrics));
  }

  listGroups(): Observable<GqlGroup[]> {
    return this.apollo
      .watchQuery<{ groups: GqlGroup[] }>({ query: Q.LIST_GROUPS, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data.groups));
  }

  listProjects(groupId?: string): Observable<GqlProject[]> {
    return this.apollo
      .watchQuery<{ projects: GqlProject[] }>({ query: Q.LIST_PROJECTS, variables: { groupId }, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data.projects));
  }

  listTasks(projectId?: string): Observable<GqlTask[]> {
    return this.apollo
      .watchQuery<{ tasks: GqlTask[] }>({ query: Q.LIST_TASKS, variables: { projectId }, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data.tasks));
  }

  listExecutions(taskId?: string, limit?: number): Observable<GqlExecution[]> {
    return this.apollo
      .watchQuery<{ executions: GqlExecution[] }>({ query: Q.LIST_EXECUTIONS, variables: { taskId, limit }, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data.executions));
  }

  getExecution(id: string): Observable<GqlExecutionDetail> {
    return this.apollo
      .watchQuery<GqlExecutionDetail>({ query: Q.GET_EXECUTION, variables: { id }, fetchPolicy: 'network-only' })
      .valueChanges.pipe(map((r) => r.data));
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  createGroup(name: string, parentId?: string): Observable<GqlGroup> {
    return this.apollo.mutate<{ createGroup: GqlGroup }>({ mutation: Q.CREATE_GROUP, variables: { name, parentId } })
      .pipe(map((r) => r.data!.createGroup));
  }

  deleteGroup(id: string): Observable<boolean> {
    return this.apollo.mutate<{ deleteGroup: boolean }>({ mutation: Q.DELETE_GROUP, variables: { id } })
      .pipe(map((r) => r.data!.deleteGroup));
  }

  createProject(name: string, groupId?: string): Observable<GqlProject> {
    return this.apollo.mutate<{ createProject: GqlProject }>({ mutation: Q.CREATE_PROJECT, variables: { name, groupId } })
      .pipe(map((r) => r.data!.createProject));
  }

  deleteProject(id: string): Observable<boolean> {
    return this.apollo.mutate<{ deleteProject: boolean }>({ mutation: Q.DELETE_PROJECT, variables: { id } })
      .pipe(map((r) => r.data!.deleteProject));
  }

  createTask(vars: { name: string; identifier: string; dsl: string; cron?: string; projectId?: string }): Observable<GqlTask> {
    return this.apollo.mutate<{ createTask: GqlTask }>({ mutation: Q.CREATE_TASK, variables: vars })
      .pipe(map((r) => r.data!.createTask));
  }

  updateTask(id: string, vars: { name?: string; dsl?: string; cron?: string; projectId?: string }): Observable<GqlTask> {
    return this.apollo.mutate<{ updateTask: GqlTask }>({ mutation: Q.UPDATE_TASK, variables: { id, ...vars } })
      .pipe(map((r) => r.data!.updateTask));
  }

  deleteTask(id: string): Observable<boolean> {
    return this.apollo.mutate<{ deleteTask: boolean }>({ mutation: Q.DELETE_TASK, variables: { id } })
      .pipe(map((r) => r.data!.deleteTask));
  }

  runTask(id: string): Observable<RunResult> {
    return this.apollo.mutate<{ runTask: RunResult }>({ mutation: Q.RUN_TASK, variables: { id } })
      .pipe(map((r) => r.data!.runTask));
  }

  stopExecution(id: string): Observable<Pick<GqlExecution, 'id' | 'status'>> {
    return this.apollo
      .mutate<{ stopExecution: Pick<GqlExecution, 'id' | 'status'> }>({ mutation: Q.STOP_EXECUTION, variables: { id } })
      .pipe(map((r) => r.data!.stopExecution));
  }

  // ── Subscriptions (Phoenix channel transport — see AbsintheSocketService) ──

  subscribeExecutionLogs(executionId: string): Observable<GqlExecutionLog> {
    return this.absinthe
      .subscribe<{ executionLog: GqlExecutionLog }>(Q.EXECUTION_LOG_SUBSCRIPTION, { executionId })
      .pipe(map((d) => d.executionLog));
  }

  subscribeExecutionStatus(executionId: string): Observable<GqlExecutionStatus> {
    return this.absinthe
      .subscribe<{ executionStatus: GqlExecutionStatus }>(Q.EXECUTION_STATUS_SUBSCRIPTION, { executionId })
      .pipe(map((d) => d.executionStatus));
  }

  /** Execution status transitions of a task (cross-job graph live overlay). */
  subscribeTaskExecution(taskId: string): Observable<GqlExecutionStatus> {
    return this.absinthe
      .subscribe<{ taskExecutionUpdated: GqlExecutionStatus }>(Q.TASK_EXECUTION_SUBSCRIPTION, { taskId })
      .pipe(map((d) => d.taskExecutionUpdated));
  }

  /** Every step status transition of an execution (create → running → terminal). */
  subscribeExecutionSteps(executionId: string): Observable<GqlStepExecution> {
    return this.absinthe
      .subscribe<{ stepUpdated: GqlStepExecution }>(Q.STEP_UPDATED_SUBSCRIPTION, { executionId })
      .pipe(map((d) => d.stepUpdated));
  }
}
