export interface AccessFlags {
  view: boolean;
  run: boolean;
  create: boolean;
  edit: boolean;
  delete: boolean;
  manageMembers: boolean;
}

export interface DataSource {
  id: number;
  name: string;
  slug: string;
  adapter: 'postgres' | 'mysql';
  host: string;
  port: number;
  databaseName: string;
  username: string;
  ssl: boolean;
  notes?: string;
  projectIds: number[];
  can?: { edit: boolean; delete: boolean };
}

export interface SmtpSettings {
  host: string;
  port: number;
  username: string;
  fromName: string;
  fromEmail: string;
  tls: 'always' | 'if_available' | 'never';
  auth: boolean;
  enabled: boolean;
  /** True when a password is stored; the password itself is never returned. */
  passwordSet: boolean;
  updatedAt?: string;
}

export interface TaskDefinition {
  id: number;
  name: string;
  /** User-provided slug; immutable. Part of the public `code`. */
  identifier?: string;
  /** Public global job id, `<identifier>-<suffix>` (e.g. `backup-uI0IOQ45`). */
  code?: string;
  description?: string | null;
  dsl: string;
  cron?: string;
  projectId?: number | null;
  releaseAt?: string | null;
  archiveAt?: string | null;
  createdAt: string;
  accessLevel?: number;
  can?: AccessFlags;
}

/**
 * A node in a job's execution flow (from GET /tasks/:id/flow). Mirrors
 * CartographBackend.Dsl.Flow: a plain step, an if/else branch, an inlined
 * sub-job (its own steps nested), or an unresolved/forbidden job reference.
 */
/** Entry of the job data sandbox listing (GET /api/files). */
export interface FileEntry {
  name: string;
  isDir: boolean;
  size: number | null;
  modifiedAt: string | null;
  /** Set on virtual entries (a member's project folders at the root), where
   *  the display name differs from the real sandbox path. */
  path?: string;
}

export interface FileListing {
  path: string;
  /** Whether the viewer may upload/delete at this path (admin, or project :edit). */
  canWrite: boolean;
  entries: FileEntry[];
}

export type FlowNode =
  | { id: string; kind: 'step'; name: string; params: Record<string, unknown> }
  | { id: string; kind: 'if'; condition: string; then: FlowNode[]; else: FlowNode[] }
  | { id: string; kind: 'job'; ref: string; name: string; taskId: number | null; cycle: boolean; steps: FlowNode[] }
  | { id: string; kind: 'job_error'; ref: string };

/** Cross-job reference graph (from GET /tasks/graph): every task the viewer
 *  can see plus the `use` edges between them. */
export interface TasksGraphNode {
  id: number;
  name: string;
  code: string;
  cron: string | null;
  projectId: number | null;
  projectName: string | null;
  groupId: number | null;
  groupName: string | null;
  /** True when the task sits on a reference cycle (bad data — flag it). */
  inCycle: boolean;
}

export interface TasksGraph {
  nodes: TasksGraphNode[];
  edges: { source: number; target: number }[];
}

export type Status =
  | 'PENDING'
  | 'RUNNING'
  | 'SUCCESS'
  | 'FAILED'
  | 'STOPPED'
  | 'SKIPPED';

export type ExecutionTrigger = 'manual' | 'cron';

export interface TaskExecution {
  id: number;
  taskDefinitionId: number;
  taskName: string;
  status: Status;
  trigger?: ExecutionTrigger;
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
}

export interface StepExecution {
  id: number;
  executionId: number;
  stepName: string;
  stepOrder: number;
  status: Status;
  startedAt?: string;
  finishedAt?: string;
  errorMessage?: string;
  /** Dsl.Flow structural id of the node that produced this step (null on old rows). */
  flowNodeId?: string | null;
}

export interface ExecutionDetail {
  execution: TaskExecution;
  steps: StepExecution[];
}

export interface ExecutionLog {
  id: number;
  executionId: number;
  stepExecutionId?: number;
  level: string;
  message: string;
  timestamp: string;
}

export interface Group {
  id: number;
  name: string;
  description?: string | null;
  parentId: number | null;
  position: number;
  createdAt: string;
  accessLevel?: number;
  can?: AccessFlags;
  code?: string;
}

export interface Project {
  id: number;
  name: string;
  description?: string | null;
  groupId: number | null;
  position: number;
  createdAt: string;
  accessLevel?: number;
  can?: AccessFlags;
  code?: string;
}

export interface User {
  id: number;
  name: string;
  email: string;
  isAdmin: boolean;
  totpEnabled: boolean;
  insertedAt: string;
}

export interface Membership {
  id: number;
  userId: number;
  subjectType: 'group' | 'project' | 'task';
  subjectId: number;
  accessLevel: number;
  levelName: string;
  user?: User;
}

export interface PickableUser {
  id: number;
  name: string;
  email: string;
}

export interface MembersResponse {
  members: Membership[];
  myLevel: number;
}

// Access levels are served by the backend (GET /api/access-levels) so the level
// catalogue lives in a single place — see CartographBackend.Authorization.
export interface AccessLevel {
  value: number;
  name: string;
  description: string;
}

export interface SystemMetrics {
  cpu: {
    usagePercent: number;
    beamUsagePercent: number;
    schedulers: number;
    logicalCores: number;
  };
  memory: {
    os: { totalMb: number; usedMb: number; freeMb: number; usedPercent: number };
    vm: { totalMb: number; processesMb: number; binaryMb: number; codeMb: number; etsMb: number };
  };
  disk: Array<{ mount: string; totalGb: number; usedPercent: number }>;
  system: {
    uptimeSeconds: number;
    processCount: number;
    atomCount: number;
    nodeName: string;
    elixirVersion: string;
    otpVersion: string;
  };
  oban: {
    available: number;
    executing: number;
    scheduled: number;
    retryable: number;
    discarded: number;
    completed: number;
  };
}

export interface TreeNode {
  type: 'group' | 'project';
  item: Group | Project;
  children: TreeNode[];
}

export interface ApiToken {
  id: number;
  name: string;
  prefix: string;
  lastUsedAt: string | null;
  expiresAt: string | null;
  createdAt: string;
}
