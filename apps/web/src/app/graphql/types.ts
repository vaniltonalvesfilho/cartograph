// Result types for the GraphQL API. Unlike the REST models in ../models, the
// GraphQL schema exposes `ID`s as strings and most fields as nullable; these
// mirror the selection sets in ./queries. Optional (`?`) fields are the ones a
// given operation may omit from its selection.

export interface DashboardMetrics {
  totalTasks: number;
  totalGroups: number;
  totalProjects: number;
  running: number;
  scheduled: number;
  successRate: number | null;
}

export interface GqlGroup {
  id: string;
  name: string;
  parentId: string | null;
  position: number | null;
  createdAt?: string | null;
}

export interface GqlProject {
  id: string;
  name: string;
  groupId: string | null;
  position: number | null;
  createdAt?: string | null;
}

export interface GqlTask {
  id: string;
  name: string;
  dsl: string;
  cron: string | null;
  projectId: string | null;
  identifier?: string | null;
  code?: string | null;
  createdAt?: string | null;
}

export interface GqlExecution {
  id: string;
  taskDefinitionId: string | null;
  taskName: string | null;
  status: string | null;
  createdAt: string | null;
  startedAt: string | null;
  finishedAt: string | null;
}

export interface GqlStepExecution {
  id: string;
  stepName: string | null;
  stepOrder: number | null;
  status: string | null;
  startedAt: string | null;
  finishedAt: string | null;
  errorMessage: string | null;
  flowNodeId?: string | null;
}

export interface GqlExecutionLog {
  id: string;
  level: string | null;
  message: string | null;
  timestamp: string | null;
  stepExecutionId?: string | null;
}

export interface GqlExecutionDetail {
  execution: GqlExecution;
  executionSteps: GqlStepExecution[];
  executionLogs: GqlExecutionLog[];
}

export interface GqlExecutionStatus {
  id: string;
  status: string | null;
  startedAt: string | null;
  finishedAt: string | null;
}

export interface RunResult {
  executionId: string;
}
