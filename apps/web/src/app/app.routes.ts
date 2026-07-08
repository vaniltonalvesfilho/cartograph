import { Routes } from '@angular/router';
import { authGuard } from './guards/auth.guard';
import { adminGuard } from './guards/admin.guard';
import { ShellComponent } from './components/shell.component';
import { LoginComponent } from './components/login.component';
import { DashboardComponent } from './components/dashboard.component';
import { TaskCreateComponent } from './components/task-create.component';
import { TaskListComponent } from './components/task-list.component';
import { ExecutionDetailComponent } from './components/execution-detail.component';

export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  // Desktop-only: pick the backend before authenticating (unguarded on purpose).
  { path: 'settings/server', loadComponent: () => import('./components/server-settings.component').then(m => m.ServerSettingsComponent) },
  {
    path: '',
    component: ShellComponent,
    canActivate: [authGuard],
    children: [
      { path: '', component: DashboardComponent },
      { path: 'tasks', component: TaskListComponent },
      { path: 'tasks/new', component: TaskCreateComponent },
      { path: 'tasks/:id', loadComponent: () => import('./components/job-detail.component').then(m => m.JobDetailComponent) },
      { path: 'tasks/:id/edit', loadComponent: () => import('./components/task-edit.component').then(m => m.TaskEditComponent) },
      { path: 'groups/:id', loadComponent: () => import('./components/group-overview.component').then(m => m.GroupOverviewComponent) },
      { path: 'projects/:id', loadComponent: () => import('./components/project-tasks.component').then(m => m.ProjectTasksComponent) },
      { path: 'executions/:id', component: ExecutionDetailComponent },
      { path: 'explore', loadComponent: () => import('./components/explore.component').then(m => m.ExploreComponent) },
      { path: 'monitor', loadComponent: () => import('./components/server-monitor.component').then(m => m.ServerMonitorComponent) },
      { path: 'admin/users', canActivate: [adminGuard], loadComponent: () => import('./components/user-management.component').then(m => m.UserManagementComponent) },
      { path: 'admin/data-sources', canActivate: [adminGuard], loadComponent: () => import('./components/admin-data-sources.component').then(m => m.AdminDataSourcesComponent) },
      { path: 'admin/smtp', canActivate: [adminGuard], loadComponent: () => import('./components/admin-smtp.component').then(m => m.AdminSmtpComponent) },
      { path: 'files', loadComponent: () => import('./components/admin-files.component').then(m => m.AdminFilesComponent) },
      { path: 'admin/files', redirectTo: 'files' },
      { path: 'profile', loadComponent: () => import('./components/profile.component').then(m => m.ProfileComponent) },
      { path: 'docs', loadComponent: () => import('./components/docs.component').then(m => m.DocsComponent) },
      { path: 'graphql', loadComponent: () => import('./components/graphql-explorer.component').then(m => m.GraphqlExplorerComponent) },
    ],
  },
  { path: '**', redirectTo: '' },
];
