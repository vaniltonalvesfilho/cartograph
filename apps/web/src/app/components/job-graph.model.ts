import ELK, { ElkNode, ElkExtendedEdge } from 'elkjs/lib/elk.bundled.js';
import { CNode, CParam, parseDsl, emitDsl, newId } from './job-canvas.model';

/**
 * Free-canvas (n8n/Node-RED style) model: a flat node-link graph the user lays
 * out by hand and wires with arrows. The DSL is a *nested* sequence (steps in
 * order, if/else with then/else, use refs), so the graph must stay **structured**
 * — the editor enforces single-next output ports and an if's two labelled ports.
 *
 *   • `dslToGraph` — parse the DSL (reusing `parseDsl`) and walk the tree into
 *     nodes + edges. Sequence → chained `out` edges; `if` → `then`/`else` edges
 *     into each branch, whose last node flows into the node after the if (merge).
 *   • `graphToDsl` — recover structured control flow from the wiring (find each
 *     if's merge = post-dominator) back into a `CNode[]` tree, then `emitDsl`.
 *     Non-structurable graphs (cycle, ambiguous merge, loose node) return an error
 *     instead of clobbering the DSL.
 *   • `layoutGraph` — ELK layered (flat) for initial / "auto-arrange" positions.
 *
 * Positions are session-only (not persisted): the DSL has no slot for them.
 */

export type GKind = 'step' | 'use' | 'if';
export type GPort = 'out' | 'then' | 'else';

export interface GNode {
  id: string;
  kind: GKind;
  x: number;
  y: number;
  name?: string;        // step
  params?: CParam[];    // step
  ref?: string;         // use
  condition?: string;   // if
}

export interface GEdge { from: string; port: GPort; to: string; }
export interface Graph { nodes: GNode[]; edges: GEdge[]; }

export const newGStep = (x = 0, y = 0): GNode => ({ id: newId(), kind: 'step', name: 'newStep', params: [], x, y });
export const newGUse  = (x = 0, y = 0): GNode => ({ id: newId(), kind: 'use', ref: '', x, y });
export const newGIf   = (x = 0, y = 0): GNode => ({ id: newId(), kind: 'if', condition: 'state["key"] > 0', x, y });

// ── DSL → graph ─────────────────────────────────────────────────────────────────

export function dslToGraph(dsl: string): { taskName: string; graph: Graph } {
  const { taskName, nodes } = parseDsl(dsl || '');
  const graph: Graph = { nodes: [], edges: [] };
  buildList(nodes, null, graph);
  return { taskName, graph };
}

/** Builds nodes for `cnodes`, whose last element flows into `contId`. Returns the entry id. */
function buildList(cnodes: CNode[], contId: string | null, g: Graph): string | null {
  let next = contId;
  for (let i = cnodes.length - 1; i >= 0; i--) next = buildNode(cnodes[i], next, g);
  return next;
}

/** Builds one CNode flowing into `contId`. Returns this node's id. */
function buildNode(c: CNode, contId: string | null, g: Graph): string {
  const id = c.id || newId();
  if (c.kind === 'step') {
    g.nodes.push({ id, kind: 'step', name: c.name, params: c.params, x: 0, y: 0 });
    if (contId) g.edges.push({ from: id, port: 'out', to: contId });
    return id;
  }
  if (c.kind === 'use') {
    g.nodes.push({ id, kind: 'use', ref: c.ref, x: 0, y: 0 });
    if (contId) g.edges.push({ from: id, port: 'out', to: contId });
    return id;
  }
  // if: branches flow into the merge (the node after the if = contId).
  g.nodes.push({ id, kind: 'if', condition: c.condition, x: 0, y: 0 });
  const thenEntry = buildList(c.then, contId, g);
  const elseEntry = buildList(c.else, contId, g);
  if (thenEntry) g.edges.push({ from: id, port: 'then', to: thenEntry });
  if (elseEntry) g.edges.push({ from: id, port: 'else', to: elseEntry });
  return id;
}

// ── graph → DSL ─────────────────────────────────────────────────────────────────

export type GraphToDsl =
  | { ok: true; dsl: string }
  | { ok: false; error: string };

export function graphToDsl(taskName: string, graph: Graph): GraphToDsl {
  if (graph.nodes.length === 0) return { ok: true, dsl: `${taskName || 'myPipeline'} {\n\n}` };

  const v = validateGraph(graph);
  if (!v.ok) return v;

  const ctx = buildCtx(graph);
  try {
    const tree = chain(ctx, v.entry, null, new Set());
    return { ok: true, dsl: emitDsl(taskName, tree) };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) };
  }
}

interface Ctx {
  byId: Map<string, GNode>;
  out: Map<string, GEdge[]>;       // from-id → its outgoing edges
}

function buildCtx(graph: Graph): Ctx {
  const byId = new Map(graph.nodes.map(n => [n.id, n] as const));
  const out = new Map<string, GEdge[]>();
  for (const e of graph.edges) (out.get(e.from) ?? out.set(e.from, []).get(e.from)!).push(e);
  return { byId, out };
}

function portTarget(ctx: Ctx, id: string, port: GPort): string | null {
  return ctx.out.get(id)?.find(e => e.port === port)?.to ?? null;
}

/** Nodes reachable from `start` (following all out edges), `stop` included but not expanded. */
function reach(ctx: Ctx, start: string | null, stop: string | null): Set<string> {
  const seen = new Set<string>();
  if (!start) return seen;
  const stack = [start];
  while (stack.length) {
    const n = stack.pop()!;
    if (seen.has(n)) continue;
    seen.add(n);
    if (n === stop) continue;
    for (const e of ctx.out.get(n) ?? []) if (!seen.has(e.to)) stack.push(e.to);
  }
  return seen;
}

/** The merge of an if = first node reachable from BOTH branches (post-dominator). */
function findMerge(ctx: Ctx, thenT: string | null, elseT: string | null, stop: string | null): string | null {
  const st = reach(ctx, thenT, stop);
  const se = reach(ctx, elseT, stop);
  const inter = [...st].filter(x => se.has(x));
  if (inter.length === 0) return stop;
  // Merge = the only candidate not reachable *from* another candidate (the earliest).
  const roots = inter.filter(c => !inter.some(o => o !== c && reach(ctx, o, stop).has(c)));
  if (roots.length !== 1) throw new Error('Flow is not structurable: ambiguous join point between branches.');
  return roots[0];
}

/** Emits a CNode[] following out-edges from `start` until reaching `stop` (merge) or end. */
function chain(ctx: Ctx, start: string | null, stop: string | null, guard: Set<string>): CNode[] {
  const out: CNode[] = [];
  let cur = start;
  while (cur && cur !== stop) {
    if (guard.has(cur)) throw new Error('Flow is not structurable: cycle detected.');
    guard.add(cur);
    const node = ctx.byId.get(cur)!;

    if (node.kind === 'if') {
      const thenT = portTarget(ctx, cur, 'then');
      const elseT = portTarget(ctx, cur, 'else');
      const merge = findMerge(ctx, thenT, elseT, stop);
      out.push({
        id: cur, kind: 'if', condition: node.condition ?? '',
        then: thenT && thenT !== merge ? chain(ctx, thenT, merge, new Set(guard)) : [],
        else: elseT && elseT !== merge ? chain(ctx, elseT, merge, new Set(guard)) : [],
      });
      cur = merge;
    } else if (node.kind === 'use') {
      out.push({ id: cur, kind: 'use', ref: node.ref ?? '' });
      cur = portTarget(ctx, cur, 'out');
    } else {
      out.push({ id: cur, kind: 'step', name: node.name ?? '', params: node.params ?? [] });
      cur = portTarget(ctx, cur, 'out');
    }
  }
  return out;
}

// ── Validation ──────────────────────────────────────────────────────────────────

type Validation = { ok: true; entry: string } | { ok: false; error: string };

export function validateGraph(graph: Graph): Validation {
  // At most one edge per (from, port).
  const seen = new Set<string>();
  for (const e of graph.edges) {
    const k = `${e.from}::${e.port}`;
    if (seen.has(k)) return { ok: false, error: 'An output port has more than one connection.' };
    seen.add(k);
  }

  // Entry = the single node with no incoming edge.
  const incoming = new Set(graph.edges.map(e => e.to));
  const roots = graph.nodes.filter(n => !incoming.has(n.id));
  if (roots.length === 0) return { ok: false, error: 'No start node (every node has an incoming edge — there is a cycle).' };
  if (roots.length > 1) return { ok: false, error: 'There are loose/disconnected nodes (more than one start point).' };

  // Every node reachable from the entry.
  const ctx = buildCtx(graph);
  const seenR = reach(ctx, roots[0].id, null);
  if (seenR.size !== graph.nodes.length) return { ok: false, error: 'There is a node disconnected from the flow.' };

  return { ok: true, entry: roots[0].id };
}

// ── Layout (ELK layered, flat) ──────────────────────────────────────────────────

export const NODE_W = 200;
export const NODE_H = 64;

const LAYOUT_OPTS = {
  'elk.algorithm': 'layered',
  'elk.direction': 'DOWN',
  'elk.layered.spacing.nodeNodeBetweenLayers': '56',
  'elk.spacing.nodeNode': '48',
  'elk.padding': '[top=20,left=20,bottom=20,right=20]',
};

/** Returns a copy of the graph with ELK-assigned x/y (for initial / auto-arrange). */
export async function layoutGraph(graph: Graph): Promise<Graph> {
  if (graph.nodes.length === 0) return graph;
  const children: ElkNode[] = graph.nodes.map(n => ({ id: n.id, width: NODE_W, height: NODE_H }));
  const edges: ElkExtendedEdge[] = graph.edges.map((e, i) => ({
    id: `e${i}`, sources: [e.from], targets: [e.to],
  }));
  const laid = await new ELK().layout({ id: 'root', layoutOptions: LAYOUT_OPTS, children, edges });
  const pos = new Map((laid.children ?? []).map(c => [c.id, { x: c.x ?? 0, y: c.y ?? 0 }] as const));
  return {
    nodes: graph.nodes.map(n => ({ ...n, ...(pos.get(n.id) ?? { x: n.x, y: n.y }) })),
    edges: graph.edges,
  };
}
