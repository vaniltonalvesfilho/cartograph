import {
  AfterViewInit,
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  ElementRef,
  Input,
  NgZone,
  OnChanges,
  OnDestroy,
  SimpleChanges,
  ViewChild,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslatePipe } from '../services/translate.pipe';
import { ApiService } from '../services/api.service';
import { GraphQLService } from '../services/graphql.service';
import { Status, TaskDefinition, TasksGraph } from '../models';

// Status colours — readable on both light and dark surfaces
const STATUS_COLOR: Record<string, string> = {
  RUNNING:  '#22c55e',   // green
  SUCCESS:  '#22c55e',   // green
  PENDING:  '#f59e0b',   // amber
  STOPPED:  '#f59e0b',   // amber
  SKIPPED:  '#f59e0b',   // amber
  FAILED:   '#ef4444',   // red
};
const COLOR_NONE = '#9ca3af'; // gray — never executed

// Hull tint per group — soft hues distinct from the status colours
const GROUP_PALETTE = [
  '#5e6ad2', '#0ea5e9', '#10b981', '#e88c30',
  '#ec4899', '#8b5cf6', '#14b8a6', '#a3a838',
];

interface FNode {
  id: string; label: string; code: string; cron?: string;
  projectId: number | null; projectName: string | null;
  groupId: number | null; groupName: string | null;
  inCycle: boolean; orphan: boolean; external: boolean;
  x: number; y: number; vx: number; vy: number;
  ax: number; ay: number;
  degree: number;
  status: Status | null;
  pinned: boolean;
}
interface FLink { source: FNode; target: FNode; }
interface Hull { d: string; color: string; label: string; lx: number; ly: number; }

@Component({
  selector: 'app-job-graph',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, TooltipDirective, TranslatePipe],
  template: `
<div class="gh" #host
     (wheel)="onWheel($event)"
     (pointerdown)="onBgDown($event)"
     (pointermove)="onMove($event)"
     (pointerup)="onUp()"
     (pointerleave)="onUp()">

  <!-- toolbar -->
  <div class="toolbar">
    <button class="cg-icon-btn" (click)="fit()" [cgTooltip]="'flow.fit' | translate">
      <app-icon>fit_screen</app-icon>
    </button>
    <button class="cg-icon-btn" (click)="zoomBy(1.25)" [cgTooltip]="'flow.zoomIn' | translate">
      <app-icon>add</app-icon>
    </button>
    <button class="cg-icon-btn" (click)="zoomBy(0.8)" [cgTooltip]="'flow.zoomOut' | translate">
      <app-icon>remove</app-icon>
    </button>
  </div>

  <!-- legend -->
  <div class="legend" *ngIf="nodes.length > 0">
    <span class="legend-dot" style="background:#22c55e"></span> {{ 'jobGraph.legendSuccess' | translate }}
    <span class="legend-dot ml" style="background:#f59e0b"></span> {{ 'jobGraph.legendPending' | translate }}
    <span class="legend-dot ml" style="background:#ef4444"></span> {{ 'jobGraph.legendFailed' | translate }}
    <span class="legend-dot ml" style="background:#9ca3af"></span> {{ 'jobGraph.legendNever' | translate }}
    <span *ngIf="hasCycles" class="legend-ring cycle ml"></span>
    <ng-container *ngIf="hasCycles">{{ 'jobGraph.legendCycle' | translate }}</ng-container>
    <span *ngIf="hasOrphans" class="legend-ring orphan ml"></span>
    <ng-container *ngIf="hasOrphans">{{ 'jobGraph.legendOrphan' | translate }}</ng-container>
    <span *ngIf="hasExternal" class="legend-ext ml">↗</span>
    <ng-container *ngIf="hasExternal">{{ 'jobGraph.external' | translate }}</ng-container>
  </div>

  <!-- graph canvas -->
  <svg #svgEl class="canvas" [class.panning]="panning">
    <defs>
      <filter id="jg-glow" x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur in="SourceGraphic" stdDeviation="5" result="b"/>
        <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
      <marker id="jg-arrow" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto">
        <path d="M0,0 L6,3 L0,6 z" class="jg-arrowhead"/>
      </marker>
    </defs>

    <g [attr.transform]="tr">
      <!-- project hulls (bottom layer) -->
      <g *ngFor="let h of hulls" class="jg-hull-g">
        <path class="jg-hull" [attr.d]="h.d" [style.fill]="h.color" [style.stroke]="h.color"/>
        <text class="jg-hull-label" [attr.x]="h.lx" [attr.y]="h.ly" [style.fill]="h.color">{{ h.label }}</text>
      </g>

      <!-- edges (below nodes) -->
      <line *ngFor="let l of links"
            class="jg-edge"
            [class.jg-edge-hi]="isEHi(l)"
            [class.jg-edge-dim]="isEDim(l)"
            [class.jg-edge-anim]="isEAnim(l)"
            [attr.x1]="ex1(l)" [attr.y1]="ey1(l)"
            [attr.x2]="ex2(l)" [attr.y2]="ey2(l)"
            marker-end="url(#jg-arrow)"/>

      <!-- nodes -->
      <g *ngFor="let n of nodes"
         class="jg-node"
         [class.jg-dim]="isDim(n)"
         [class.jg-ext]="n.external"
         [attr.transform]="'translate('+n.x+','+n.y+')'"
         (pointerdown)="onNodeDown($event, n)"
         (dblclick)="nav(n)"
         (mouseenter)="hov(n)"
         (mouseleave)="hov(null)">

        <title>{{ n.label }} ({{ n.code }})</title>

        <!-- outer glow ring -->
        <circle class="jg-glow"
                [attr.r]="nr(n) + 6"
                [style.fill]="nc(n)"
                [style.opacity]="hovId===n.id ? 0.4 : isNbr(n) ? 0.25 : 0.1"/>

        <!-- main dot -->
        <circle class="jg-dot"
                [attr.r]="nr(n)"
                [style.fill]="nc(n)"
                [class.jg-dot-hi]="hovId===n.id || isNbr(n)"/>

        <!-- reference-cycle warning ring -->
        <circle *ngIf="n.inCycle"
                class="jg-cycle-ring"
                [attr.r]="nr(n) + 4.5"/>

        <!-- orphan (unconnected) ring -->
        <circle *ngIf="n.orphan && !n.inCycle"
                class="jg-orphan-ring"
                [attr.r]="nr(n) + 4.5"/>

        <!-- cron indicator ring -->
        <circle *ngIf="n.cron"
                class="jg-cron-ring"
                [attr.r]="nr(n) + 2.5"
                [style.stroke]="'#f59e0b'"/>

        <!-- label -->
        <text class="jg-label"
              [attr.y]="nr(n) + 15"
              [class.jg-label-hi]="hovId===n.id">{{ n.label }}</text>
        <text *ngIf="n.external && n.projectName"
              class="jg-ext-text"
              [attr.y]="nr(n) + 27">↗ {{ n.projectName }}</text>
        <text *ngIf="n.cron && !n.external"
              class="jg-cron-text"
              [attr.y]="nr(n) + 26">{{ n.cron }}</text>
      </g>
    </g>
  </svg>

  <!-- empty state -->
  <div *ngIf="nodes.length === 0" class="jg-empty">
    <app-icon>device_hub</app-icon>
    <span>{{ 'jobGraph.empty' | translate }}</span>
  </div>
</div>
  `,
  styles: [`
:host { display: block; }

.gh {
  position: relative;
  width: 100%;
  height: 500px;
  background: var(--cg-surface);
  background-image: radial-gradient(circle, var(--cg-border-strong) 1px, transparent 1px);
  background-size: 28px 28px;
  border-radius: var(--cg-radius, 10px);
  overflow: hidden;
  touch-action: none;
  border: 1px solid var(--cg-border);
  user-select: none;
}

/* toolbar */
.toolbar {
  position: absolute; top: 8px; right: 8px; z-index: 10;
  display: flex; gap: 2px;
  background: var(--cg-surface-2);
  border: 1px solid var(--cg-border);
  border-radius: 8px; padding: 2px;
}
.toolbar button { width: 32px; height: 32px; color: var(--cg-text-muted); border: none; background: transparent; cursor: pointer; border-radius: 6px; }
.toolbar button:hover { color: var(--cg-text); background: var(--cg-sidebar-hover, rgba(127,127,127,0.12)); }

/* legend */
.legend {
  position: absolute; bottom: 10px; left: 12px; z-index: 10;
  font-size: 10px; color: var(--cg-text-muted);
  display: flex; align-items: center; gap: 5px; flex-wrap: wrap;
  max-width: calc(100% - 24px);
}
.legend-dot {
  display: inline-block; width: 7px; height: 7px;
  border-radius: 50%;
}
.legend-ring {
  display: inline-block; width: 9px; height: 9px;
  border-radius: 50%; box-sizing: border-box;
}
.legend-ring.cycle  { border: 1.5px dashed #ef4444; }
.legend-ring.orphan { border: 1.5px dotted #9ca3af; }
.legend-ext { font-size: 11px; line-height: 1; }
.legend-dot.ml, .legend-ring.ml, .legend-ext.ml { margin-left: 8px; }

/* canvas */
.canvas { width: 100%; height: 100%; display: block; cursor: grab; }
.canvas.panning { cursor: grabbing; }

/* project hulls */
.jg-hull {
  fill-opacity: 0.05;
  stroke-opacity: 0.14;
  stroke-width: 26;
  stroke-linejoin: round;
  pointer-events: none;
}
.jg-hull-label {
  font-size: 11px;
  font-weight: 600;
  font-family: Inter, -apple-system, sans-serif;
  opacity: 0.75;
  pointer-events: none;
}

/* edges */
.jg-edge {
  stroke: var(--cg-border-strong);
  stroke-width: 1.2;
  fill: none;
  transition: stroke 0.12s, opacity 0.12s;
}
.jg-edge-hi {
  stroke: var(--cg-text-muted) !important;
  stroke-width: 1.8 !important;
}
.jg-edge-dim { opacity: 0.15 !important; }
.jg-arrowhead { fill: var(--cg-text-muted); opacity: 0.55; }

@keyframes jg-flow {
  to { stroke-dashoffset: -24; }
}
.jg-edge-anim {
  stroke: #22c55e !important;
  stroke-width: 2.2 !important;
  stroke-dasharray: 8 5;
  animation: jg-flow 0.55s linear infinite;
  opacity: 1 !important;
  filter: drop-shadow(0 0 3px #22c55e88);
}

/* nodes */
.jg-node { cursor: pointer; }
.jg-glow {
  pointer-events: none;
  filter: url(#jg-glow);
  transition: opacity 0.15s;
}
.jg-dot {
  transition: r 0.15s, opacity 0.15s, filter 0.15s;
}
.jg-dot-hi { filter: brightness(1.2); }
.jg-dim .jg-dot  { opacity: 0.15 !important; }
.jg-dim .jg-glow { opacity: 0.02 !important; }
.jg-dim .jg-label { opacity: 0.15 !important; }

/* external (outside the focused project) */
.jg-ext .jg-dot  { opacity: 0.45; }
.jg-ext .jg-glow { opacity: 0.04 !important; }
.jg-ext .jg-label { opacity: 0.6; font-style: italic; }

.jg-cycle-ring {
  fill: none;
  stroke: #ef4444;
  stroke-width: 1.6;
  stroke-dasharray: 4 3;
  pointer-events: none;
}
.jg-orphan-ring {
  fill: none;
  stroke: #9ca3af;
  stroke-width: 1.2;
  stroke-dasharray: 1.5 3;
  stroke-linecap: round;
  opacity: 0.8;
  pointer-events: none;
}
.jg-cron-ring {
  fill: none;
  stroke-width: 1.2;
  stroke-dasharray: 3 2;
  opacity: 0.6;
  pointer-events: none;
}

/* labels */
.jg-label {
  fill: var(--cg-text);
  font-size: 12px;
  font-family: Inter, -apple-system, sans-serif;
  text-anchor: middle;
  pointer-events: none;
  transition: fill 0.12s, opacity 0.12s;
  opacity: 0.85;
}
.jg-label-hi { opacity: 1 !important; font-weight: 600; }
.jg-cron-text {
  fill: #f59e0b;
  opacity: 0.75;
  font-size: 9px;
  font-family: ui-monospace, monospace;
  text-anchor: middle;
  pointer-events: none;
}
.jg-ext-text {
  fill: var(--cg-text-muted);
  font-size: 9px;
  font-family: Inter, -apple-system, sans-serif;
  text-anchor: middle;
  pointer-events: none;
}

/* empty state */
.jg-empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  gap: 10px; color: var(--cg-text-muted);
  font-size: 13px;
}
.jg-empty app-icon { font-size: 44px; width: 44px; height: 44px; }
  `],
})
export class JobGraphComponent implements OnChanges, AfterViewInit, OnDestroy {
  /** Focus set: the graph shows these tasks plus their direct neighbors. */
  @Input() tasks: TaskDefinition[] = [];
  @ViewChild('host') hostRef?: ElementRef<HTMLElement>;
  @ViewChild('svgEl') svgRef?: ElementRef<SVGElement>;

  nodes: FNode[] = [];
  links: FLink[] = [];
  hulls: Hull[] = [];

  hasCycles = false;
  hasOrphans = false;
  hasExternal = false;

  hovId: string | null = null;
  private nbrIds = new Set<string>();

  scale = 1; tx = 0; ty = 0;
  panning = false;

  private W = 600; private H = 500;
  private alpha = 0;
  private rafId?: number;
  private lx = 0; private ly = 0;
  private dragNode: FNode | null = null;
  private viewReady = false;

  get tr(): string { return `translate(${this.tx},${this.ty}) scale(${this.scale})`; }

  private graph: TasksGraph | null = null;
  private latestStatus = new Map<string, Status>();
  private pollId?: ReturnType<typeof setInterval>;
  private statusSubs: Subscription[] = [];
  private subscribedIds = '';

  constructor(
    private cdr: ChangeDetectorRef,
    private router: Router,
    private api: ApiService,
    private gql: GraphQLService,
    private zone: NgZone,
  ) {}

  ngAfterViewInit(): void {
    this.viewReady = true;
    const el = this.hostRef?.nativeElement;
    if (el) { this.W = el.clientWidth; this.H = el.clientHeight; }
    if (this.nodes.length) this.initSim();
    this.startPolling();
  }

  ngOnChanges(c: SimpleChanges): void {
    if (c['tasks']) {
      this.api.tasksGraph().subscribe({
        next: g => {
          this.graph = g;
          this.fetchStatus().then(() => {
            this.buildGraph();
            this.openStatusSubscriptions();
            if (this.viewReady) this.initSim();
            this.cdr.markForCheck();
          });
        },
        error: () => { /* keep whatever is on screen */ },
      });
    }
  }

  ngOnDestroy(): void {
    cancelAnimationFrame(this.rafId!);
    if (this.pollId) clearInterval(this.pollId);
    this.closeStatusSubscriptions();
  }

  // ── Live status polling ─────────────────────────────────────────────────────

  /** Fetch the latest execution status per task into `latestStatus`. */
  private fetchStatus(): Promise<void> {
    return new Promise(resolve => {
      this.api.listExecutions().subscribe({
        next: execs => {
          this.latestStatus.clear();
          for (const e of execs) {
            const key = String(e.taskDefinitionId);
            if (!this.latestStatus.has(key)) this.latestStatus.set(key, e.status);
          }
          resolve();
        },
        error: () => resolve(),
      });
    });
  }

  /**
   * One GraphQL subscription per visible task recolours its node in place —
   * without rebuilding the graph or resetting the force layout, so node
   * positions stay put while a running job lights up its outgoing edges.
   */
  private openStatusSubscriptions(): void {
    // Rebuilds with the same node set (input refreshes) keep the live channels.
    const ids = this.nodes.map((n) => n.id).sort().join(',');
    if (ids === this.subscribedIds) return;
    this.subscribedIds = ids;

    this.closeStatusSubscriptions();
    // Look the node up by id at event time — `nodes` is rebuilt on input
    // changes and a captured object would go stale.
    this.statusSubs = this.nodes.map(({ id }) =>
      this.gql.subscribeTaskExecution(id).subscribe({
        next: (exec) => {
          this.zone.run(() => {
            const status = (exec.status as Status) ?? null;
            this.latestStatus.set(id, status as Status);
            const node = this.nodes.find((x) => x.id === id);
            if (node && node.status !== status) { node.status = status; this.cdr.markForCheck(); }
          });
        },
      })
    );
  }

  private closeStatusSubscriptions(): void {
    for (const s of this.statusSubs) s.unsubscribe();
    this.statusSubs = [];
  }

  /** Slow fallback for missed events (reconnects, page opened mid-run). */
  private startPolling(): void {
    this.pollId = setInterval(() => {
      this.fetchStatus().then(() => {
        let changed = false;
        for (const n of this.nodes) {
          const next = this.latestStatus.get(n.id) ?? null;
          if (next !== n.status) { n.status = next; changed = true; }
        }
        if (changed) this.cdr.markForCheck();
      });
    }, 10_000);
  }

  // ── Graph construction ──────────────────────────────────────────────────────

  /**
   * Shown subgraph = focus tasks (the input) plus their direct neighbors from
   * the server graph. Neighbors outside the focus set render dimmed with an
   * "↗ project" hint — a project view still shows its external dependencies.
   */
  private buildGraph(): void {
    const g = this.graph ?? { nodes: [], edges: [] };
    const focus = new Set(this.tasks.map(t => t.id));

    // degree over the FULL graph — an orphan is a job nothing references at all
    const fullDegree = new Map<number, number>();
    for (const e of g.edges) {
      fullDegree.set(e.source, (fullDegree.get(e.source) ?? 0) + 1);
      fullDegree.set(e.target, (fullDegree.get(e.target) ?? 0) + 1);
    }

    const shown = new Set<number>(focus);
    for (const e of g.edges) {
      if (focus.has(e.source)) shown.add(e.target);
      if (focus.has(e.target)) shown.add(e.source);
    }

    const byId = new Map<number, FNode>();
    this.nodes = g.nodes
      .filter(n => shown.has(n.id))
      .map(n => {
        const node: FNode = {
          id: String(n.id), label: n.name, code: n.code, cron: n.cron ?? undefined,
          projectId: n.projectId, projectName: n.projectName,
          groupId: n.groupId, groupName: n.groupName,
          inCycle: n.inCycle,
          orphan: (fullDegree.get(n.id) ?? 0) === 0,
          external: !focus.has(n.id),
          x: Math.random() * this.W, y: Math.random() * this.H,
          vx: 0, vy: 0, ax: 0, ay: 0,
          degree: 0, status: this.latestStatus.get(String(n.id)) ?? null,
          pinned: false,
        };
        byId.set(n.id, node);
        return node;
      });

    this.links = [];
    for (const e of g.edges) {
      const s = byId.get(e.source), t = byId.get(e.target);
      if (!s || !t) continue;
      s.degree++; t.degree++;
      this.links.push({ source: s, target: t });
    }

    this.hasCycles = this.nodes.some(n => n.inCycle);
    this.hasOrphans = this.nodes.some(n => n.orphan);
    this.hasExternal = this.nodes.some(n => n.external);
  }

  // ── Force simulation ────────────────────────────────────────────────────────

  private initSim(): void {
    cancelAnimationFrame(this.rafId!);
    const n = this.nodes.length;
    if (!n) { this.hulls = []; return; }
    // start positions clustered per project so hulls settle apart nicely
    const clusters = [...new Set(this.nodes.map(nd => this.clusterKey(nd)))];
    const R = Math.min(this.W, this.H) * 0.30;
    this.nodes.forEach(nd => {
      const ci = clusters.indexOf(this.clusterKey(nd));
      const a = (ci / Math.max(clusters.length, 1)) * 2 * Math.PI - Math.PI / 2;
      nd.x = this.W / 2 + R * Math.cos(a) + (Math.random() - 0.5) * 60;
      nd.y = this.H / 2 + R * Math.sin(a) + (Math.random() - 0.5) * 60;
      nd.vx = 0; nd.vy = 0;
    });
    this.tx = 0; this.ty = 0; this.scale = 1;
    this.alpha = 1;
    this.fitted = false;
    this.rafId = requestAnimationFrame(this.tick);
  }

  private clusterKey(n: FNode): string {
    return n.projectId != null ? `p${n.projectId}` : 'none';
  }

  private fitted = false;

  private tick = (): void => {
    if (this.alpha < 0.002 && !this.dragNode) {
      this.updateHulls();
      if (!this.fitted) { this.fitted = true; this.fit(); }
      this.cdr.markForCheck();
      return;
    }
    this.applyForces();
    this.alpha = Math.max(0, this.alpha * 0.975 - 0.001);
    this.updateHulls();
    this.cdr.markForCheck();
    this.rafId = requestAnimationFrame(this.tick);
  };

  private applyForces(): void {
    const cx = this.W / 2, cy = this.H / 2;
    const a  = this.alpha;

    for (const n of this.nodes) { n.ax = 0; n.ay = 0; }

    // Link spring (rest length 140 px)
    for (const l of this.links) {
      const dx = l.target.x - l.source.x;
      const dy = l.target.y - l.source.y;
      const d  = Math.sqrt(dx * dx + dy * dy) || 1;
      const f  = (d - 140) * 0.045;
      l.source.ax += (dx / d) * f;
      l.source.ay += (dy / d) * f;
      l.target.ax -= (dx / d) * f;
      l.target.ay -= (dy / d) * f;
    }

    // Many-body repulsion O(n²) — fine for < ~100 nodes
    const rep = 1800 * a;
    for (let i = 0; i < this.nodes.length; i++) {
      for (let j = i + 1; j < this.nodes.length; j++) {
        const dx = this.nodes[j].x - this.nodes[i].x;
        const dy = this.nodes[j].y - this.nodes[i].y;
        const d2 = Math.max(dx * dx + dy * dy, 400);
        const f  = rep / d2;
        this.nodes[i].ax -= dx * f;
        this.nodes[i].ay -= dy * f;
        this.nodes[j].ax += dx * f;
        this.nodes[j].ay += dy * f;
      }
    }

    // Cluster gravity: pull same-project nodes toward their centroid so the
    // hull blobs stay coherent and separate from each other.
    const centroids = new Map<string, { x: number; y: number; n: number }>();
    for (const n of this.nodes) {
      const k = this.clusterKey(n);
      const c = centroids.get(k) ?? { x: 0, y: 0, n: 0 };
      c.x += n.x; c.y += n.y; c.n++;
      centroids.set(k, c);
    }
    for (const n of this.nodes) {
      const c = centroids.get(this.clusterKey(n))!;
      if (c.n < 2) continue;
      n.ax += (c.x / c.n - n.x) * 0.06 * a;
      n.ay += (c.y / c.n - n.y) * 0.06 * a;
    }

    // Gentle center gravity so graph doesn't drift away
    for (const n of this.nodes) {
      n.ax += (cx - n.x) * 0.04 * a;
      n.ay += (cy - n.y) * 0.04 * a;
    }

    // Integrate (velocity Verlet-ish with damping)
    for (const n of this.nodes) {
      if (n.pinned) continue;
      n.vx = (n.vx + n.ax) * 0.87;
      n.vy = (n.vy + n.ay) * 0.87;
      n.x += n.vx;
      n.y += n.vy;
    }
  }

  // ── Project hulls ───────────────────────────────────────────────────────────

  private updateHulls(): void {
    const byProject = new Map<string, FNode[]>();
    for (const n of this.nodes) {
      if (n.projectId == null) continue;
      const k = `p${n.projectId}`;
      (byProject.get(k) ?? byProject.set(k, []).get(k)!).push(n);
    }

    const hulls: Hull[] = [];
    for (const members of byProject.values()) {
      // each node contributes 8 padded circle points; hull of the union
      const pts: [number, number][] = [];
      for (const n of members) {
        const r = this.nr(n) + 14;
        for (let i = 0; i < 8; i++) {
          const a = (i / 8) * 2 * Math.PI;
          pts.push([n.x + r * Math.cos(a), n.y + r * Math.sin(a)]);
        }
      }
      const hull = convexHull(pts);
      if (hull.length < 3) continue;

      // label above the topmost hull point
      let top = hull[0];
      for (const p of hull) if (p[1] < top[1]) top = p;

      const first = members[0];
      const color = GROUP_PALETTE[
        Math.abs(first.groupId ?? first.projectId ?? 0) % GROUP_PALETTE.length
      ];
      const label = first.groupName
        ? `${first.groupName} / ${first.projectName}`
        : `${first.projectName}`;

      hulls.push({
        d: 'M' + hull.map(p => `${p[0]},${p[1]}`).join('L') + 'Z',
        color, label,
        lx: top[0] - 10, ly: top[1] - 30,
      });
    }
    this.hulls = hulls;
  }

  // ── Visual helpers ──────────────────────────────────────────────────────────

  nr(n: FNode): number { return 12 + Math.min(n.degree, 6) * 2.5; }
  nc(n: FNode): string { return n.status ? (STATUS_COLOR[n.status] ?? COLOR_NONE) : COLOR_NONE; }

  isNbr(n: FNode): boolean { return this.hovId !== null && this.nbrIds.has(n.id); }
  isDim(n: FNode): boolean { return this.hovId !== null && this.hovId !== n.id && !this.nbrIds.has(n.id); }
  isEHi(l: FLink): boolean  { return this.hovId !== null && (l.source.id === this.hovId || l.target.id === this.hovId); }
  isEDim(l: FLink): boolean { return this.hovId !== null && l.source.id !== this.hovId && l.target.id !== this.hovId; }
  // A running job is walking through its referenced jobs — animate its outgoing
  // edges to show the reference being executed.
  isEAnim(l: FLink): boolean {
    return l.source.status === 'RUNNING';
  }

  // Edge endpoints: start past source circle, end before target circle
  private _ep(l: FLink, atTarget: boolean, gap: number): [number, number] {
    const dx = l.target.x - l.source.x;
    const dy = l.target.y - l.source.y;
    const d  = Math.sqrt(dx * dx + dy * dy) || 1;
    if (atTarget) {
      const r = this.nr(l.target) + gap;
      return [l.target.x - (dx / d) * r, l.target.y - (dy / d) * r];
    }
    const r = this.nr(l.source) + 2;
    return [l.source.x + (dx / d) * r, l.source.y + (dy / d) * r];
  }
  ex1(l: FLink): number { return this._ep(l, false, 0)[0]; }
  ey1(l: FLink): number { return this._ep(l, false, 0)[1]; }
  ex2(l: FLink): number { return this._ep(l, true, 8)[0]; }
  ey2(l: FLink): number { return this._ep(l, true, 8)[1]; }

  // ── Hover ───────────────────────────────────────────────────────────────────

  hov(n: FNode | null): void {
    this.hovId = n?.id ?? null;
    this.nbrIds.clear();
    if (n) {
      for (const l of this.links) {
        if (l.source.id === n.id) this.nbrIds.add(l.target.id);
        if (l.target.id === n.id) this.nbrIds.add(l.source.id);
      }
    }
    this.cdr.markForCheck();
  }

  nav(n: FNode): void { this.router.navigate(['/tasks', n.id]); }

  // ── Pointer events ──────────────────────────────────────────────────────────

  onNodeDown(ev: PointerEvent, n: FNode): void {
    ev.stopPropagation();
    this.dragNode = n;
    n.pinned = true;
    this.lx = ev.clientX;
    this.ly = ev.clientY;
    if (this.alpha < 0.05) {
      this.alpha = 0.35;
      this.rafId = requestAnimationFrame(this.tick);
    }
  }

  onBgDown(ev: PointerEvent): void {
    this.panning = true;
    this.lx = ev.clientX;
    this.ly = ev.clientY;
  }

  onMove(ev: PointerEvent): void {
    const dx = ev.clientX - this.lx;
    const dy = ev.clientY - this.ly;
    this.lx = ev.clientX;
    this.ly = ev.clientY;

    if (this.dragNode) {
      this.dragNode.x += dx / this.scale;
      this.dragNode.y += dy / this.scale;
      this.updateHulls();
      this.cdr.markForCheck();
    } else if (this.panning) {
      this.tx += dx;
      this.ty += dy;
      this.cdr.markForCheck();
    }
  }

  onUp(): void {
    if (this.dragNode) { this.dragNode.pinned = false; this.dragNode = null; }
    this.panning = false;
  }

  onWheel(ev: WheelEvent): void {
    ev.preventDefault();
    const rect = (ev.currentTarget as HTMLElement).getBoundingClientRect();
    this.zoomAt(ev.clientX - rect.left, ev.clientY - rect.top, ev.deltaY < 0 ? 1.12 : 0.89);
  }

  /** Zoom/pan so every node (plus hull + label padding) is visible. */
  fit(): void {
    if (!this.nodes.length) { this.tx = 0; this.ty = 0; this.scale = 1; return; }
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const n of this.nodes) {
      minX = Math.min(minX, n.x); maxX = Math.max(maxX, n.x);
      minY = Math.min(minY, n.y); maxY = Math.max(maxY, n.y);
    }
    const pad = 80;
    const w = maxX - minX + pad * 2, h = maxY - minY + pad * 2;
    this.scale = Math.min(this.W / w, this.H / h, 1.6);
    this.tx = this.W / 2 - this.scale * (minX + maxX) / 2;
    this.ty = this.H / 2 - this.scale * (minY + maxY) / 2;
    this.cdr.markForCheck();
  }

  zoomBy(f: number): void { this.zoomAt(this.W / 2, this.H / 2, f); }

  private zoomAt(px: number, py: number, f: number): void {
    const next = Math.min(4, Math.max(0.1, this.scale * f));
    const k    = next / this.scale;
    this.tx    = px - (px - this.tx) * k;
    this.ty    = py - (py - this.ty) * k;
    this.scale = next;
    this.cdr.markForCheck();
  }
}

// Andrew's monotone chain — returns the hull in counter-clockwise order.
function convexHull(pts: [number, number][]): [number, number][] {
  if (pts.length < 3) return pts;
  const p = [...pts].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const cross = (o: number[], a: number[], b: number[]) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);

  const lower: [number, number][] = [];
  for (const pt of p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], pt) <= 0) lower.pop();
    lower.push(pt);
  }
  const upper: [number, number][] = [];
  for (const pt of [...p].reverse()) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], pt) <= 0) upper.pop();
    upper.push(pt);
  }
  lower.pop(); upper.pop();
  return [...lower, ...upper];
}
