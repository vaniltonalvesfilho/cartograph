import { gql } from 'apollo-angular';

// ── Queries ───────────────────────────────────────────────────────────────────

export const DASHBOARD_METRICS = gql`
  query DashboardMetrics {
    dashboardMetrics {
      totalTasks
      totalGroups
      totalProjects
      running
      scheduled
      successRate
    }
  }
`;

export const LIST_GROUPS = gql`
  query ListGroups {
    groups {
      id name parentId position createdAt
    }
  }
`;

export const LIST_PROJECTS = gql`
  query ListProjects($groupId: ID) {
    projects(groupId: $groupId) {
      id name groupId position createdAt
    }
  }
`;

export const LIST_TASKS = gql`
  query ListTasks($projectId: ID) {
    tasks(projectId: $projectId) {
      id name identifier code dsl cron projectId createdAt
    }
  }
`;

export const LIST_EXECUTIONS = gql`
  query ListExecutions($taskId: ID, $limit: Int) {
    executions(taskId: $taskId, limit: $limit) {
      id taskDefinitionId taskName status createdAt startedAt finishedAt
    }
  }
`;

export const GET_EXECUTION = gql`
  query GetExecution($id: ID!) {
    execution(id: $id) {
      id taskDefinitionId taskName status createdAt startedAt finishedAt
    }
    executionSteps(executionId: $id) {
      id stepName stepOrder status startedAt finishedAt errorMessage flowNodeId
    }
    executionLogs(executionId: $id) {
      id level message timestamp
    }
  }
`;

// ── Mutations ─────────────────────────────────────────────────────────────────

export const CREATE_GROUP = gql`
  mutation CreateGroup($name: String!, $parentId: ID) {
    createGroup(name: $name, parentId: $parentId) {
      id name parentId position
    }
  }
`;

export const DELETE_GROUP = gql`
  mutation DeleteGroup($id: ID!) {
    deleteGroup(id: $id)
  }
`;

export const CREATE_PROJECT = gql`
  mutation CreateProject($name: String!, $groupId: ID) {
    createProject(name: $name, groupId: $groupId) {
      id name groupId position
    }
  }
`;

export const DELETE_PROJECT = gql`
  mutation DeleteProject($id: ID!) {
    deleteProject(id: $id)
  }
`;

export const CREATE_TASK = gql`
  mutation CreateTask($name: String!, $identifier: String!, $dsl: String!, $cron: String, $projectId: ID) {
    createTask(name: $name, identifier: $identifier, dsl: $dsl, cron: $cron, projectId: $projectId) {
      id name identifier code dsl cron projectId
    }
  }
`;

export const UPDATE_TASK = gql`
  mutation UpdateTask($id: ID!, $name: String, $dsl: String, $cron: String, $projectId: ID) {
    updateTask(id: $id, name: $name, dsl: $dsl, cron: $cron, projectId: $projectId) {
      id name dsl cron projectId
    }
  }
`;

export const DELETE_TASK = gql`
  mutation DeleteTask($id: ID!) {
    deleteTask(id: $id)
  }
`;

export const RUN_TASK = gql`
  mutation RunTask($id: ID!) {
    runTask(id: $id) {
      executionId
    }
  }
`;

export const STOP_EXECUTION = gql`
  mutation StopExecution($id: ID!) {
    stopExecution(id: $id) {
      id status
    }
  }
`;

// ── Subscriptions ─────────────────────────────────────────────────────────────

export const EXECUTION_LOG_SUBSCRIPTION = gql`
  subscription ExecutionLog($executionId: ID!) {
    executionLog(executionId: $executionId) {
      id level message timestamp stepExecutionId
    }
  }
`;

export const EXECUTION_STATUS_SUBSCRIPTION = gql`
  subscription ExecutionStatus($executionId: ID!) {
    executionStatus(executionId: $executionId) {
      id status startedAt finishedAt
    }
  }
`;

export const TASK_EXECUTION_SUBSCRIPTION = gql`
  subscription TaskExecutionUpdated($taskId: ID!) {
    taskExecutionUpdated(taskId: $taskId) {
      id status startedAt finishedAt
    }
  }
`;

export const STEP_UPDATED_SUBSCRIPTION = gql`
  subscription StepUpdated($executionId: ID!) {
    stepUpdated(executionId: $executionId) {
      id stepName stepOrder status startedAt finishedAt errorMessage flowNodeId
      agentUsage {
        model inputTokens outputTokens cacheReadInputTokens
        estimatedCostUsd stopReason durationMs
      }
    }
  }
`;
