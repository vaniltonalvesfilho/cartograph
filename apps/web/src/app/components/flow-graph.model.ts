import ELK, { ElkNode, ElkExtendedEdge } from 'elkjs/lib/elk.bundled.js';
import { FlowNode } from '../models';

/**
 * Turns a job's Flow tree (FlowNode[]) into a laid-out graph ready to draw.
 *
 * The flow is expressed as nested **compound** boxes — a sub-job (`use`) and the
 * two branches of an `if` become containers holding their own vertical chain —
 * so branching/provenance reads as nesting rather than edge spaghetti. ELK
 * (layered, top-down) computes positions; we flatten them to absolute SVG
 * coordinates. The renderer is otherwise library-agnostic.
 */

export type GKind = 'step' | 'job' | 'job_error' | 'if' | 'branch';

export interface GNode {
  id: string;
  kind: GKind;
  title: string;
  sub?: string;
  /** sub-job target for navigation. */
  taskId?: number | null;
  ref?: string;
  cycle?: boolean;
  branch?: 'then' | 'else';
  container: boolean;
  x: number;
  y: number;
  w: number;
  h: number;
  depth: number;
}

export interface GEdge {
  id: string;
  points: { x: number; y: number }[];
}

export interface FlowGraph {
  nodes: GNode[];
  edges: GEdge[];
  width: number;
  height: number;
}

interface Meta {
  kind: GKind;
  title: string;
  sub?: string;
  taskId?: number | null;
  ref?: string;
  cycle?: boolean;
  branch?: 'then' | 'else';
  container: boolean;
}

const HEADER = 34; // top padding reserved inside a container for its header
const LEAF_H = 52;
const ERR_H = 48;

const ROOT_OPTS = {
  'elk.algorithm': 'layered',
  'elk.direction': 'DOWN',
  'elk.hierarchyHandling': 'INCLUDE_CHILDREN',
  'elk.layered.spacing.nodeNodeBetweenLayers': '30',
  'elk.spacing.nodeNode': '26',
  'elk.padding': '[top=10,left=10,bottom=10,right=10]',
};

const CONTAINER_OPTS = {
  'elk.padding': `[top=${HEADER},left=14,bottom=14,right=14]`,
  'elk.spacing.nodeNode': '24',
};

function leafWidth(title: string, sub?: string): number {
  const t = title.length * 7.4;
  const s = (sub?.length ?? 0) * 6.6;
  return Math.min(320, Math.max(160, Math.ceil(Math.max(t, s)) + 52));
}

/** Builds the ELK input tree while recording per-id render metadata. */
function buildElk(flow: FlowNode[], meta: Map<string, Meta>): ElkNode {
  const root: ElkNode = { id: 'root', layoutOptions: ROOT_OPTS, ...chain(flow, meta) };
  return root;
}

/** A vertical chain: children laid out top-down + sequential edges between them. */
function chain(nodes: FlowNode[], meta: Map<string, Meta>): { children: ElkNode[]; edges: ElkExtendedEdge[] } {
  const children = nodes.map(n => elkOf(n, meta));
  const edges: ElkExtendedEdge[] = [];
  for (let i = 0; i < children.length - 1; i++) {
    edges.push({ id: `e_${children[i].id}_${children[i + 1].id}`, sources: [children[i].id], targets: [children[i + 1].id] });
  }
  return { children, edges };
}

function elkOf(node: FlowNode, meta: Map<string, Meta>): ElkNode {
  switch (node.kind) {
    case 'step': {
      const sub = paramSummary(node.params);
      meta.set(node.id, { kind: 'step', title: node.name, sub, container: false });
      return { id: node.id, width: leafWidth(node.name, sub), height: LEAF_H };
    }
    case 'job_error': {
      meta.set(node.id, { kind: 'job_error', title: node.ref, container: false });
      return { id: node.id, width: leafWidth(node.ref), height: ERR_H };
    }
    case 'job': {
      meta.set(node.id, {
        kind: 'job', title: node.name, sub: node.ref, taskId: node.taskId,
        ref: node.ref, cycle: node.cycle, container: true,
      });
      const inner = chain(node.steps, meta);
      return { id: node.id, layoutOptions: CONTAINER_OPTS, ...inner };
    }
    case 'if': {
      meta.set(node.id, { kind: 'if', title: node.condition, container: true });
      const branches: ElkNode[] = [];
      branches.push(branchOf(`${node.id}::then`, 'then', node.then, meta));
      branches.push(branchOf(`${node.id}::else`, 'else', node.else, meta));
      // No edges between branches → ELK places them in the same layer (side by side).
      return { id: node.id, layoutOptions: CONTAINER_OPTS, children: branches, edges: [] };
    }
    default:
      return { id: (node as FlowNode).id, width: 160, height: LEAF_H };
  }
}

function branchOf(id: string, side: 'then' | 'else', nodes: FlowNode[], meta: Map<string, Meta>): ElkNode {
  meta.set(id, { kind: 'branch', title: side, branch: side, container: true });
  const inner = chain(nodes, meta);
  // A placeholder keeps an empty branch from collapsing to nothing.
  if (inner.children.length === 0) {
    const ph = `${id}::empty`;
    meta.set(ph, { kind: 'step', title: '—', container: false });
    inner.children.push({ id: ph, width: 120, height: 36 });
  }
  return { id, layoutOptions: CONTAINER_OPTS, ...inner };
}

/** Flattens the laid-out ELK tree into absolute-coordinate GNodes/GEdges. */
function flatten(elk: ElkNode, meta: Map<string, Meta>): FlowGraph {
  const gnodes: GNode[] = [];
  const gedges: GEdge[] = [];

  const walk = (n: ElkNode, ox: number, oy: number, depth: number) => {
    const x = ox + (n.x ?? 0);
    const y = oy + (n.y ?? 0);

    if (n.id !== 'root') {
      const m = meta.get(n.id);
      if (m) {
        gnodes.push({
          id: n.id, kind: m.kind, title: m.title, sub: m.sub, taskId: m.taskId,
          ref: m.ref, cycle: m.cycle, branch: m.branch, container: m.container,
          x, y, w: n.width ?? 0, h: n.height ?? 0, depth,
        });
      }
    }

    for (const e of n.edges ?? []) {
      for (const s of e.sections ?? []) {
        const pts = [s.startPoint, ...(s.bendPoints ?? []), s.endPoint].map(p => ({ x: x + p.x, y: y + p.y }));
        gedges.push({ id: e.id, points: pts });
      }
    }

    for (const c of n.children ?? []) walk(c, x, y, n.id === 'root' ? 0 : depth + 1);
  };

  walk(elk, 0, 0, -1);
  return { nodes: gnodes, edges: gedges, width: elk.width ?? 0, height: elk.height ?? 0 };
}

export async function layoutFlow(flow: FlowNode[]): Promise<FlowGraph> {
  const meta = new Map<string, Meta>();
  const graph = buildElk(flow, meta);
  const elk = new ELK();
  const laid = await elk.layout(graph);
  return flatten(laid, meta);
}

export function paramSummary(params: Record<string, unknown>): string {
  return Object.entries(params || {})
    .map(([k, v]) => `${k} ${typeof v === 'string' ? `"${v}"` : v}`)
    .join(' · ');
}
