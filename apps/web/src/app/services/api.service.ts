import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';
import {
  AccessLevel,
  DataSource,
  SmtpSettings,
  ExecutionDetail,
  ExecutionLog,
  FileListing,
  Group,
  Membership,
  MembersResponse,
  PickableUser,
  Project,
  FlowNode,
  SystemMetrics,
  TaskDefinition,
  TasksGraph,
  TaskExecution,
  User,
  ApiToken,
} from '../models';
import { environment } from '../../environments/environment';

const BASE = environment.apiBase;

@Injectable({ providedIn: 'root' })
export class ApiService {
  constructor(private http: HttpClient) {}

  // ---- Tasks ----
  listTasks(opts?: { projectId?: number }): Observable<TaskDefinition[]> {
    const params = opts?.projectId != null
      ? new HttpParams().set('projectId', opts.projectId)
      : undefined;
    return this.http.get<TaskDefinition[]>(`${BASE}/tasks`, { params });
  }

  availableSteps(): Observable<string[]> {
    return this.http.get<string[]>(`${BASE}/tasks/steps`);
  }

  createTask(body: { name: string; identifier: string; dsl: string; cron?: string; projectId?: number | null; releaseAt?: string | null; archiveAt?: string | null }): Observable<TaskDefinition> {
    return this.http.post<TaskDefinition>(`${BASE}/tasks`, body);
  }

  updateTask(id: number, body: Partial<{ name: string; dsl: string; cron: string | null; projectId: number | null; releaseAt: string | null; archiveAt: string | null }>): Observable<TaskDefinition> {
    return this.http.put<TaskDefinition>(`${BASE}/tasks/${id}`, body);
  }

  deleteTask(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/tasks/${id}`);
  }

  tasksGraph(): Observable<TasksGraph> {
    return this.http.get<TasksGraph>(`${BASE}/tasks/graph`);
  }

  taskFlow(id: number): Observable<FlowNode[]> {
    return this.http
      .get<{ flow: FlowNode[] }>(`${BASE}/tasks/${id}/flow`)
      .pipe(map(r => r.flow));
  }

  runTask(id: number): Observable<{ executionId: number }> {
    return this.http.post<{ executionId: number }>(`${BASE}/tasks/${id}/run`, {});
  }

  // ---- Groups ----
  listGroups(): Observable<Group[]> {
    return this.http.get<Group[]>(`${BASE}/groups`);
  }

  createGroup(body: { name: string; description?: string; parentId?: number | null }): Observable<Group> {
    return this.http.post<Group>(`${BASE}/groups`, body);
  }

  updateGroup(id: number, body: Partial<Group>): Observable<Group> {
    return this.http.put<Group>(`${BASE}/groups/${id}`, body);
  }

  deleteGroup(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/groups/${id}`);
  }

  // ---- Projects ----
  listProjects(opts?: { groupId?: number | 'root' }): Observable<Project[]> {
    const params = opts?.groupId != null
      ? new HttpParams().set('groupId', String(opts.groupId))
      : undefined;
    return this.http.get<Project[]>(`${BASE}/projects`, { params });
  }

  createProject(body: { name: string; description?: string; groupId?: number | null }): Observable<Project> {
    return this.http.post<Project>(`${BASE}/projects`, body);
  }

  updateProject(id: number, body: Partial<Project>): Observable<Project> {
    return this.http.put<Project>(`${BASE}/projects/${id}`, body);
  }

  deleteProject(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/projects/${id}`);
  }

  // ---- Executions ----
  listExecutions(taskId?: number): Observable<TaskExecution[]> {
    const q = taskId ? `?taskId=${taskId}` : '';
    return this.http.get<TaskExecution[]>(`${BASE}/executions${q}`);
  }

  getExecution(id: number): Observable<ExecutionDetail> {
    return this.http.get<ExecutionDetail>(`${BASE}/executions/${id}`);
  }

  getLogs(id: number): Observable<ExecutionLog[]> {
    return this.http.get<ExecutionLog[]>(`${BASE}/executions/${id}/logs`);
  }

  stop(id: number): Observable<unknown> {
    return this.http.post(`${BASE}/executions/${id}/stop`, {});
  }

  logStreamUrl(id: number): string {
    return `${BASE}/executions/${id}/logs/stream`;
  }

  // ---- System ----
  getSystemMetrics(): Observable<SystemMetrics> {
    return this.http.get<SystemMetrics>(`${BASE}/system/metrics`);
  }

  // ---- Users (admin) ----
  listUsers(): Observable<User[]> {
    return this.http.get<User[]>(`${BASE}/users`);
  }

  createUser(body: { name: string; email: string; password: string; isAdmin?: boolean }): Observable<User> {
    return this.http.post<User>(`${BASE}/users`, body);
  }

  updateUser(id: number, body: Partial<{ name: string; email: string; password: string; isAdmin: boolean }>): Observable<User> {
    return this.http.put<User>(`${BASE}/users/${id}`, body);
  }

  deleteUser(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/users/${id}`);
  }

  // Minimal user directory for member pickers (any authenticated user)
  listPickableUsers(): Observable<PickableUser[]> {
    return this.http.get<PickableUser[]>(`${BASE}/users/pickable`);
  }

  // ---- Members ----
  getAccessLevels(): Observable<AccessLevel[]> {
    return this.http.get<AccessLevel[]>(`${BASE}/access-levels`);
  }

  getGroupMembers(groupId: number): Observable<MembersResponse> {
    return this.http.get<MembersResponse>(`${BASE}/groups/${groupId}/members`);
  }

  addGroupMember(groupId: number, body: { userId: number; accessLevel: number }): Observable<Membership> {
    return this.http.post<Membership>(`${BASE}/groups/${groupId}/members`, body);
  }

  removeGroupMember(groupId: number, userId: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/groups/${groupId}/members/${userId}`);
  }

  getProjectMembers(projectId: number): Observable<MembersResponse> {
    return this.http.get<MembersResponse>(`${BASE}/projects/${projectId}/members`);
  }

  addProjectMember(projectId: number, body: { userId: number; accessLevel: number }): Observable<Membership> {
    return this.http.post<Membership>(`${BASE}/projects/${projectId}/members`, body);
  }

  removeProjectMember(projectId: number, userId: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/projects/${projectId}/members/${userId}`);
  }

  getTaskMembers(taskId: number): Observable<MembersResponse> {
    return this.http.get<MembersResponse>(`${BASE}/tasks/${taskId}/members`);
  }

  addTaskMember(taskId: number, body: { userId: number; accessLevel: number }): Observable<Membership> {
    return this.http.post<Membership>(`${BASE}/tasks/${taskId}/members`, body);
  }

  removeTaskMember(taskId: number, userId: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/tasks/${taskId}/members/${userId}`);
  }

  // ---- Data Sources (admin) ----
  listDataSources(): Observable<DataSource[]> {
    return this.http.get<DataSource[]>(`${BASE}/data-sources`);
  }

  createDataSource(attrs: Partial<DataSource> & { password?: string }): Observable<DataSource> {
    return this.http.post<DataSource>(`${BASE}/data-sources`, { data_source: attrs });
  }

  updateDataSource(id: number, attrs: Partial<DataSource> & { password?: string }): Observable<DataSource> {
    return this.http.put<DataSource>(`${BASE}/data-sources/${id}`, { data_source: attrs });
  }

  deleteDataSource(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/data-sources/${id}`);
  }

  checkDataSourceHealth(id: number): Observable<{ status: string; latencyMs?: number; error?: string }> {
    return this.http.get<any>(`${BASE}/data-sources/${id}/health`);
  }

  // ---- Project-scoped data sources ----
  listProjectDataSources(projectId: number): Observable<DataSource[]> {
    return this.http.get<DataSource[]>(`${BASE}/projects/${projectId}/data-sources`);
  }

  assignDataSourceToProject(projectId: number, dataSourceId: number): Observable<void> {
    return this.http.post<void>(`${BASE}/projects/${projectId}/data-sources/${dataSourceId}`, {});
  }

  unassignDataSourceFromProject(projectId: number, dataSourceId: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/projects/${projectId}/data-sources/${dataSourceId}`);
  }

  // ---- SMTP settings (admin) ----
  getSmtpSettings(): Observable<SmtpSettings> {
    return this.http.get<SmtpSettings>(`${BASE}/smtp-settings`);
  }

  updateSmtpSettings(attrs: Record<string, unknown>): Observable<SmtpSettings> {
    return this.http.put<SmtpSettings>(`${BASE}/smtp-settings`, { smtp: attrs });
  }

  sendSmtpTest(): Observable<{ status: string; sentTo?: string; error?: string }> {
    return this.http.post<{ status: string; sentTo?: string; error?: string }>(`${BASE}/smtp-settings/test`, {});
  }

  // ---- Files (job data sandbox, admin-only) ----
  listFiles(path: string): Observable<FileListing> {
    return this.http.get<FileListing>(`${BASE}/files`, { params: new HttpParams().set('path', path) });
  }

  uploadFile(path: string, file: File): Observable<{ path: string }> {
    const form = new FormData();
    form.append('file', file);
    form.append('path', path);
    return this.http.post<{ path: string }>(`${BASE}/files`, form);
  }

  createFolder(path: string, name: string): Observable<{ path: string }> {
    return this.http.post<{ path: string }>(`${BASE}/files/mkdir`, { path, name });
  }

  downloadFile(path: string): Observable<Blob> {
    return this.http.get(`${BASE}/files/download`, {
      params: new HttpParams().set('path', path),
      responseType: 'blob',
    });
  }

  deleteFile(path: string): Observable<void> {
    return this.http.delete<void>(`${BASE}/files`, { params: new HttpParams().set('path', path) });
  }

  // ---- 2FA / TOTP ----
  getTotpSetup(): Observable<{ secret: string; uri: string }> {
    return this.http.get<{ secret: string; uri: string }>(`${BASE}/auth/2fa/setup`);
  }

  enableTotp(code: string): Observable<{ ok: boolean }> {
    return this.http.post<{ ok: boolean }>(`${BASE}/auth/2fa/enable`, { code });
  }

  disableTotp(): Observable<{ ok: boolean }> {
    return this.http.delete<{ ok: boolean }>(`${BASE}/auth/2fa/disable`);
  }

  listApiTokens(): Observable<{ tokens: ApiToken[] }> {
    return this.http.get<{ tokens: ApiToken[] }>(`${BASE}/tokens`);
  }

  createApiToken(name: string, expiresAt?: string): Observable<{ token: ApiToken; rawToken: string }> {
    return this.http.post<{ token: ApiToken; rawToken: string }>(`${BASE}/tokens`, { name, expiresAt: expiresAt ?? null });
  }

  revokeApiToken(id: number): Observable<void> {
    return this.http.delete<void>(`${BASE}/tokens/${id}`);
  }
}
