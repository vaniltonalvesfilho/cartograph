import {
  Component, Input, Output, EventEmitter, OnChanges, SimpleChanges, AfterViewInit,
  ElementRef, ViewChild, ChangeDetectionStrategy, ChangeDetectorRef,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslatePipe } from '../services/translate.pipe';
import {
  GNode, GEdge, GPort, GKind, NODE_W, NODE_H,
  dslToGraph, graphToDsl, layoutGraph, newGStep, newGUse, newGIf,
} from './job-graph.model';

type Pt = { x: number; y: number };

/**
 * Free-canvas low-code editor (n8n/Node-RED style). The user drops nodes anywhere
 * and wires them with arrows; the flow's topology is converted to/from the DSL via
 * `job-graph.model.ts`. Positions are session-only (auto-arranged on load via ELK).
 * Two-way bound with the DSL editor through [dsl]/(dslChange).
 */
@Component({
  selector: 'app-job-canvas',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, FormsModule, IconComponent, TooltipDirective, TranslatePipe],
  template: `
<div class="jc-wrap">

  <div class="jc-toolbar">
    <app-icon class="jc-logo">schema</app-icon>
    <input class="jc-title-input" [(ngModel)]="taskName" (ngModelChange)="sync()" placeholder="task name" />
    <div class="jc-sep"></div>
    <button class="cg-btn" (click)="addNode('step')"><app-icon>add</app-icon> Step</button>
    <button class="cg-btn" (click)="addNode('use')"><app-icon>link</app-icon> Job Ref</button>
    <button class="cg-btn" (click)="addNode('if')"><app-icon>call_split</app-icon> If/Else</button>
    <div class="jc-sep"></div>
    <button class="cg-icon-btn" (click)="autoArrange()" [cgTooltip]="'jobCanvas.autoArrange' | translate"><app-icon>account_tree</app-icon></button>
    <button class="cg-icon-btn" (click)="fit()" [cgTooltip]="'flow.fit' | translate"><app-icon>fit_screen</app-icon></button>
    <button class="cg-icon-btn" (click)="zoomBy(1.2)" [cgTooltip]="'flow.zoomIn' | translate"><app-icon>add</app-icon></button>
    <button class="cg-icon-btn" (click)="zoomBy(0.83)" [cgTooltip]="'flow.zoomOut' | translate"><app-icon>remove</app-icon></button>
    <button class="cg-icon-btn" (click)="reloadFromDsl()" [cgTooltip]="'jobCanvas.resync' | translate"><app-icon>sync</app-icon></button>
  </div>

  <div class="jc-body">
    <div class="jc-canvas" #host
         (wheel)="onWheel($event)"
         (pointerdown)="onBgDown($event)"
         (pointermove)="onMove($event)"
         (pointerup)="onUp($event)"
         (pointerleave)="onUp($event)">

      <div class="jc-empty" *ngIf="!nodes.length">
        <app-icon>account_tree</app-icon>
        <p>{{ 'jobCanvas.empty' | translate }}</p>
        <p class="jc-empty-sub" [innerHTML]="'jobCanvas.emptySub' | translate"></p>
      </div>

      <svg *ngIf="nodes.length" class="jc-svg" [class.grabbing]="mode==='pan'||mode==='node'">
        <defs>
          <marker id="jcg-arrow" markerWidth="9" markerHeight="9" refX="7" refY="4" orient="auto">
            <path d="M0,0 L8,4 L0,8 z" class="jc-arrowhead" />
          </marker>
        </defs>
        <g [attr.transform]="'translate(' + tx + ',' + ty + ') scale(' + scale + ')'">

          <!-- Edges -->
          <g *ngFor="let e of edges; let i = index" class="jc-edge-g" (pointerdown)="onEdgeDown($event, i)">
            <path class="jc-edge-hit" [attr.d]="edgePath(e)"></path>
            <path class="jc-edge" [attr.d]="edgePath(e)" marker-end="url(#jcg-arrow)"></path>
          </g>

          <!-- Ghost edge while drawing -->
          <path *ngIf="draw" class="jc-edge ghost" [attr.d]="ghostPath()"></path>

          <!-- Nodes -->
          <g *ngFor="let n of nodes" [attr.transform]="'translate(' + n.x + ',' + n.y + ')'"
             class="jc-node" [ngClass]="'k-' + n.kind" [class.selected]="n.id === selectedId">

            <rect class="box" [attr.width]="W" [attr.height]="H" rx="10" ry="10"
                  (pointerdown)="onNodeDown($event, n)"></rect>

            <text class="kindlbl" x="12" y="20">{{ n.kind === 'if' ? 'IF' : n.kind === 'use' ? 'USE' : 'STEP' }}</text>
            <text class="title" x="12" y="41">{{ trunc(nodeTitle(n), W - 24, 7.6) }}</text>
            <text *ngIf="n.kind === 'step' && paramHint(n)" class="sub mono" x="12" y="56">{{ trunc(paramHint(n), W - 24, 6.4) }}</text>

            <!-- input port (top) -->
            <circle class="port in" [attr.cx]="W/2" cy="0" r="6"></circle>

            <!-- output ports (bottom) -->
            <ng-container *ngIf="n.kind === 'if'; else oneOut">
              <circle class="port out then" [attr.cx]="W*0.3" [attr.cy]="H" r="6" (pointerdown)="onPortDown($event, n, 'then')"></circle>
              <text class="portlbl then" [attr.x]="W*0.3" [attr.y]="H+16">then</text>
              <circle class="port out else" [attr.cx]="W*0.7" [attr.cy]="H" r="6" (pointerdown)="onPortDown($event, n, 'else')"></circle>
              <text class="portlbl else" [attr.x]="W*0.7" [attr.y]="H+16">else</text>
            </ng-container>
            <ng-template #oneOut>
              <circle class="port out" [attr.cx]="W/2" [attr.cy]="H" r="6" (pointerdown)="onPortDown($event, n, 'out')"></circle>
            </ng-template>
          </g>
        </g>
      </svg>
    </div>

    <!-- Right panel -->
    <div class="jc-panel">
      <ng-container *ngIf="selectedNode as sel; else dslPreview">
        <div class="jc-panel-hd">
          <app-icon>tune</app-icon>
          <span>{{ (sel.kind === 'if' ? 'jobCanvas.panelIf' : sel.kind === 'use' ? 'jobCanvas.panelUse' : 'jobCanvas.panelStep') | translate }}</span>
          <button class="cg-icon-btn jc-del" (click)="deleteSelected()" [cgTooltip]="'jobCanvas.deleteNode' | translate"><app-icon>delete</app-icon></button>
        </div>
        <div class="jc-panel-bd">
          <ng-container *ngIf="sel.kind === 'step'">
            <div class="cg-field">
              <label class="cg-label">{{ 'jobCanvas.stepName' | translate }}</label>
              <input class="cg-input" [(ngModel)]="sel.name" (ngModelChange)="sync()" placeholder="ex: readDirectory" />
            </div>
            <div class="jc-params-hd">
              <span class="cg-label" style="margin:0;">{{ 'jobCanvas.params' | translate }}</span>
              <button class="cg-icon-btn" (click)="addParam(sel)"><app-icon>add</app-icon></button>
            </div>
            <p class="jc-params-empty" *ngIf="!sel.params?.length">{{ 'jobCanvas.noParams' | translate }}</p>
            <div *ngFor="let p of sel.params; let i = index" class="jc-param-row">
              <input class="cg-input" [(ngModel)]="p.key" (ngModelChange)="sync()" [placeholder]="'jobCanvas.phKey' | translate" style="width:84px;flex-shrink:0;" />
              <input class="cg-input" [(ngModel)]="p.value" (ngModelChange)="sync()" [placeholder]="'jobCanvas.phValue' | translate" style="flex:1;min-width:0;" />
              <button class="cg-icon-btn" (click)="removeParam(sel, i)"><app-icon>close</app-icon></button>
            </div>
          </ng-container>
          <ng-container *ngIf="sel.kind === 'use'">
            <div class="cg-field">
              <label class="cg-label">{{ 'jobCanvas.jobCode' | translate }}</label>
              <input class="cg-input" [(ngModel)]="sel.ref" (ngModelChange)="sync()" placeholder="ex: backup-Ab2cDe3f" />
            </div>
          </ng-container>
          <ng-container *ngIf="sel.kind === 'if'">
            <div class="cg-field">
              <label class="cg-label">{{ 'jobCanvas.condition' | translate }}</label>
              <input class="cg-input mono" [(ngModel)]="sel.condition" (ngModelChange)="sync()" placeholder='state["count"] > 0' />
              <span class="field-hint" [innerHTML]="'jobCanvas.ifHint' | translate"></span>
            </div>
          </ng-container>
        </div>
      </ng-container>

      <ng-template #dslPreview>
        <div class="jc-panel-hd"><app-icon>code</app-icon><span>{{ 'jobCanvas.dslGenerated' | translate }}</span></div>
        <div class="jc-err" *ngIf="dslError">
          <app-icon>warning</app-icon><span>{{ dslError }}</span>
        </div>
        <div class="jc-dsl-prev"><pre>{{ genDsl || ('jobCanvas.dslEmpty' | translate) }}</pre></div>
        <div class="jc-hint"><app-icon>touch_app</app-icon> {{ 'jobCanvas.bottomHint' | translate }}</div>
      </ng-template>
    </div>
  </div>
</div>
  `,
  styles: [`
    :host { display: block; }
    .jc-wrap { display: flex; flex-direction: column; border: 1px solid var(--cg-border);
      border-radius: var(--cg-radius); background: var(--cg-surface); overflow: hidden; height: 560px; }

    .jc-toolbar { display: flex; align-items: center; gap: 6px; padding: 8px 14px;
      border-bottom: 1px solid var(--cg-border); background: var(--cg-surface); flex-shrink: 0; }
    .jc-logo { color: var(--cg-accent); font-size: 20px; width: 20px; height: 20px; flex-shrink: 0; }
    .jc-title-input { font: 600 13px/1 inherit; color: var(--cg-text); background: transparent;
      border: 1px solid transparent; border-radius: 4px; padding: 4px 7px; outline: none; width: 150px; }
    .jc-title-input:hover { border-color: var(--cg-border-strong); }
    .jc-title-input:focus { border-color: var(--cg-accent); background: var(--cg-surface-2); }
    .jc-sep { width: 1px; height: 20px; background: var(--cg-border); margin: 0 2px; flex-shrink: 0; }

    .jc-body { display: flex; flex: 1; overflow: hidden; }
    .jc-canvas { flex: 1; position: relative; overflow: hidden; background-color: var(--cg-content-bg);
      background-image: radial-gradient(circle, var(--cg-border-strong) 1.5px, transparent 1.5px);
      background-size: 24px 24px; touch-action: none; }

    .jc-empty { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center;
      justify-content: center; gap: 8px; color: var(--cg-text-muted); font-size: 13px; text-align: center; }
    .jc-empty p { margin: 0; }
    .jc-empty app-icon { font-size: 52px; width: 52px; height: 52px; opacity: .18; }
    .jc-empty-sub { font-size: 12px; opacity: .8; line-height: 1.7; margin-top: 4px !important; }

    .jc-svg { position: absolute; inset: 0; width: 100%; height: 100%; cursor: grab; display: block;
      user-select: none; -webkit-user-select: none; }
    .jc-svg.grabbing { cursor: grabbing; }

    .jc-edge { fill: none; stroke: var(--cg-accent); stroke-width: 2; opacity: .7; }
    .jc-edge.ghost { stroke-dasharray: 5 4; opacity: .9; pointer-events: none; }
    .jc-edge-hit { fill: none; stroke: transparent; stroke-width: 14; cursor: pointer; }
    .jc-edge-g:hover .jc-edge { stroke-width: 3; opacity: 1; }
    .jc-arrowhead { fill: var(--cg-accent); opacity: .85; }

    .jc-node .box { fill: var(--cg-surface); stroke: var(--cg-border-strong); stroke-width: 1.4; cursor: grab; }
    .jc-node.selected .box { stroke: var(--cg-accent); stroke-width: 2.2; }
    .jc-node .kindlbl { font: 700 9px/1 inherit; letter-spacing: .6px; fill: var(--cg-text-muted); pointer-events: none; }
    .jc-node .title { font: 600 14px/1 'JetBrains Mono', monospace; fill: var(--cg-text); pointer-events: none; }
    .jc-node .sub { fill: var(--cg-text-muted); font-size: 11px; pointer-events: none; }
    .mono { font-family: 'JetBrains Mono', ui-monospace, monospace; }

    .k-use .box { fill: rgba(249,115,22,.06); stroke: #f97316aa; }
    .k-use .kindlbl, .k-use .title { fill: #f97316; }
    .k-if .box { fill: rgba(168,85,247,.06); stroke: #a855f7aa; }
    .k-if .kindlbl, .k-if .title { fill: #a855f7; }

    .port { fill: var(--cg-surface); stroke: var(--cg-accent); stroke-width: 2; }
    .port.in { pointer-events: none; }
    .port.out { cursor: crosshair; }
    .port.out:hover { fill: var(--cg-accent); r: 8; }
    .port.then { stroke: #34d399; } .port.else { stroke: #f59e0b; }
    .portlbl { font: 700 9px/1 inherit; text-transform: uppercase; letter-spacing: .4px; text-anchor: middle; pointer-events: none; }
    .portlbl.then { fill: #34d399; } .portlbl.else { fill: #f59e0b; }

    .jc-panel { width: 300px; flex-shrink: 0; border-left: 1px solid var(--cg-border);
      display: flex; flex-direction: column; background: var(--cg-surface); overflow: hidden; }
    .jc-panel-hd { display: flex; align-items: center; gap: 8px; padding: 12px 14px; font: 600 13px/1 inherit;
      border-bottom: 1px solid var(--cg-border); flex-shrink: 0; color: var(--cg-text); }
    .jc-panel-hd app-icon { font-size: 16px; width: 16px; height: 16px; color: var(--cg-text-muted); }
    .jc-del { margin-left: auto; }
    .jc-panel-bd { flex: 1; overflow-y: auto; padding: 14px; display: flex; flex-direction: column; gap: 12px; }
    .jc-params-hd { display: flex; align-items: center; justify-content: space-between; margin-top: 2px; }
    .jc-params-empty { font-size: 12px; color: var(--cg-text-muted); font-style: italic; margin: 0; }
    .jc-param-row { display: flex; gap: 6px; align-items: center; }
    .field-hint { font-size: 11px; color: var(--cg-text-muted); margin-top: 4px; display: block; }

    .jc-err { display: flex; gap: 8px; align-items: flex-start; padding: 10px 14px; margin: 10px;
      background: rgba(229,72,77,.08); border: 1px solid rgba(229,72,77,.3); border-radius: 8px;
      color: #e5484d; font-size: 12px; line-height: 1.45; }
    .jc-err app-icon { font-size: 16px; width: 16px; height: 16px; flex-shrink: 0; }
    .jc-dsl-prev { flex: 1; overflow: auto; }
    .jc-dsl-prev pre { margin: 0; padding: 14px; font: 11.5px/1.65 'JetBrains Mono', monospace; color: var(--cg-text); white-space: pre; }
    .jc-hint { display: flex; align-items: center; gap: 6px; padding: 10px 14px; font-size: 11px;
      color: var(--cg-text-muted); border-top: 1px solid var(--cg-border); flex-shrink: 0; }
    .jc-hint app-icon { font-size: 14px; width: 14px; height: 14px; }
  `],
})
export class JobCanvasComponent implements OnChanges, AfterViewInit {
  @Input() dsl = '';
  @Output() dslChange = new EventEmitter<string>();
  @ViewChild('host') host?: ElementRef<HTMLElement>;

  readonly W = NODE_W;
  readonly H = NODE_H;

  taskName = 'myPipeline';
  nodes: GNode[] = [];
  edges: GEdge[] = [];
  selectedId: string | null = null;
  genDsl = '';
  dslError: string | null = null;

  scale = 1; tx = 0; ty = 0;

  mode: 'pan' | 'node' | 'edge' | null = null;
  private moved = false;
  private lastX = 0; private lastY = 0;
  private dragNode: GNode | null = null;
  draw: { from: GNode; port: GPort } | null = null;
  cursor: Pt = { x: 0, y: 0 };  // canvas-space cursor while drawing an edge

  private viewReady = false;

  constructor(private cdr: ChangeDetectorRef) {}

  ngAfterViewInit(): void { this.viewReady = true; if (this.nodes.length) this.fit(); }

  ngOnChanges(ch: SimpleChanges): void {
    if (ch['dsl'] && this.dsl && this.dsl !== this.genDsl) this.reloadFromDsl();
  }

  get selectedNode(): GNode | undefined {
    return this.selectedId ? this.nodes.find(n => n.id === this.selectedId) : undefined;
  }

  // ── DSL ↔ graph ───────────────────────────────────────────────────────────────

  reloadFromDsl(): void {
    const { taskName, graph } = dslToGraph(this.dsl || '');
    this.taskName = taskName;
    this.selectedId = null;
    this.genDsl = this.dsl;
    layoutGraph(graph).then(g => {
      this.nodes = g.nodes; this.edges = g.edges;
      this.dslError = null;
      this.cdr.markForCheck();
      if (this.viewReady) setTimeout(() => this.fit());
    });
  }

  /** Graph → DSL on every topology/content change. Invalid graphs warn without clobbering. */
  sync(): void {
    const r = graphToDsl(this.taskName, { nodes: this.nodes, edges: this.edges });
    if (r.ok) { this.dslError = null; this.genDsl = r.dsl; this.dslChange.emit(r.dsl); }
    else { this.dslError = r.error; }
    this.cdr.markForCheck();
  }

  // ── Node / edge ops ──────────────────────────────────────────────────────────

  addNode(kind: GKind): void {
    const c = this.viewCenter();
    const n = kind === 'step' ? newGStep(c.x, c.y) : kind === 'use' ? newGUse(c.x, c.y) : newGIf(c.x, c.y);
    this.nodes = [...this.nodes, n];
    this.selectedId = n.id;
    this.sync();
  }

  deleteSelected(): void {
    if (!this.selectedId) return;
    this.nodes = this.nodes.filter(n => n.id !== this.selectedId);
    this.edges = this.edges.filter(e => e.from !== this.selectedId && e.to !== this.selectedId);
    this.selectedId = null;
    this.sync();
  }

  onEdgeDown(ev: PointerEvent, i: number): void {
    ev.stopPropagation();
    this.edges = this.edges.filter((_, j) => j !== i);  // click an edge → delete it
    this.sync();
  }

  addParam(step: GNode): void { step.params = [...(step.params ?? []), { key: '', value: '' }]; this.cdr.markForCheck(); }
  removeParam(step: GNode, i: number): void { step.params = (step.params ?? []).filter((_, j) => j !== i); this.sync(); }

  private connect(from: GNode, port: GPort, to: GNode): void {
    if (from.id === to.id) return;                        // no self-loop
    if (this.reaches(to.id, from.id)) { this.dslError = 'Connection would create a cycle.'; this.cdr.markForCheck(); return; }
    // single-next: drop any existing edge from this port, then add.
    this.edges = this.edges.filter(e => !(e.from === from.id && e.port === port));
    this.edges = [...this.edges, { from: from.id, port, to: to.id }];
    this.sync();
  }

  /** Is `b` reachable from `a` over current edges? (cycle guard for new links) */
  private reaches(a: string, b: string): boolean {
    const seen = new Set<string>(); const stack = [a];
    while (stack.length) {
      const n = stack.pop()!; if (n === b) return true;
      if (seen.has(n)) continue; seen.add(n);
      for (const e of this.edges) if (e.from === n) stack.push(e.to);
    }
    return false;
  }

  // ── Geometry ─────────────────────────────────────────────────────────────────

  private nodeById(id: string): GNode | undefined { return this.nodes.find(n => n.id === id); }

  inPt(n: GNode): Pt { return { x: n.x + this.W / 2, y: n.y }; }
  outPt(n: GNode, port: GPort): Pt {
    const fx = port === 'then' ? 0.3 : port === 'else' ? 0.7 : 0.5;
    return { x: n.x + this.W * fx, y: n.y + this.H };
  }

  edgePath(e: GEdge): string {
    const f = this.nodeById(e.from), t = this.nodeById(e.to);
    if (!f || !t) return '';
    return this.bezier(this.outPt(f, e.port), this.inPt(t));
  }
  ghostPath(): string {
    if (!this.draw) return '';
    return this.bezier(this.outPt(this.draw.from, this.draw.port), this.cursor);
  }
  private bezier(a: Pt, b: Pt): string {
    const dy = Math.max(40, Math.abs(b.y - a.y) * 0.5);
    return `M ${a.x} ${a.y} C ${a.x} ${a.y + dy} ${b.x} ${b.y - dy} ${b.x} ${b.y}`;
  }

  nodeTitle(n: GNode): string {
    if (n.kind === 'use') return n.ref || '(job ref)';
    if (n.kind === 'if') return n.condition || '(condition)';
    return n.name || '(no name)';
  }
  paramHint(n: GNode): string {
    return (n.params ?? []).filter(p => p.key.trim()).map(p => `${p.key} ${p.value}`).join(' · ');
  }
  trunc(text: string, maxW: number, charPx: number): string {
    if (!text) return '';
    const max = Math.max(3, Math.floor(maxW / charPx));
    return text.length > max ? text.slice(0, max - 1) + '…' : text;
  }

  // ── Pointer: pan / node-drag / edge-draw ───────────────────────────────────────

  private toCanvas(ev: PointerEvent): Pt {
    const r = this.host!.nativeElement.getBoundingClientRect();
    return { x: (ev.clientX - r.left - this.tx) / this.scale, y: (ev.clientY - r.top - this.ty) / this.scale };
  }

  onBgDown(ev: PointerEvent): void { this.mode = 'pan'; this.moved = false; this.lastX = ev.clientX; this.lastY = ev.clientY; }

  onNodeDown(ev: PointerEvent, n: GNode): void {
    ev.stopPropagation();
    this.mode = 'node'; this.moved = false; this.dragNode = n;
    this.lastX = ev.clientX; this.lastY = ev.clientY;
  }

  onPortDown(ev: PointerEvent, n: GNode, port: GPort): void {
    ev.stopPropagation();
    this.mode = 'edge'; this.draw = { from: n, port }; this.cursor = this.outPt(n, port);
    this.cdr.markForCheck();
  }

  onMove(ev: PointerEvent): void {
    if (this.mode === 'pan') {
      const dx = ev.clientX - this.lastX, dy = ev.clientY - this.lastY;
      if (Math.abs(dx) + Math.abs(dy) > 2) this.moved = true;
      this.tx += dx; this.ty += dy; this.lastX = ev.clientX; this.lastY = ev.clientY;
      this.cdr.markForCheck();
    } else if (this.mode === 'node' && this.dragNode) {
      const dx = (ev.clientX - this.lastX) / this.scale, dy = (ev.clientY - this.lastY) / this.scale;
      if (Math.abs(ev.clientX - this.lastX) + Math.abs(ev.clientY - this.lastY) > 2) this.moved = true;
      this.dragNode.x += dx; this.dragNode.y += dy;
      this.lastX = ev.clientX; this.lastY = ev.clientY;
      this.cdr.markForCheck();   // edges follow via edgePath(); positions don't touch the DSL
    } else if (this.mode === 'edge') {
      this.cursor = this.toCanvas(ev);
      this.cdr.markForCheck();
    }
  }

  onUp(ev: PointerEvent): void {
    if (this.mode === 'node') {
      if (!this.moved) { this.selectedId = this.dragNode!.id; }   // click = select
      this.dragNode = null;
    } else if (this.mode === 'edge' && this.draw) {
      const hit = this.inPortHit(this.toCanvas(ev));
      if (hit) this.connect(this.draw.from, this.draw.port, hit);
      this.draw = null;
    } else if (this.mode === 'pan' && !this.moved) {
      this.selectedId = null;
    }
    this.mode = null;
    this.cdr.markForCheck();
  }

  /** Finds a node whose input port is within reach of point `p` (edge drop target). */
  private inPortHit(p: Pt): GNode | undefined {
    const R = 26;
    return this.nodes.find(n => {
      if (this.draw && n.id === this.draw.from.id) return false;
      const ip = this.inPt(n);
      return Math.hypot(ip.x - p.x, ip.y - p.y) <= R;
    });
  }

  // ── View: pan / zoom / fit / auto-arrange ───────────────────────────────────────

  private viewCenter(): Pt {
    const el = this.host?.nativeElement;
    const w = el?.clientWidth ?? 600, h = el?.clientHeight ?? 400;
    return { x: (w / 2 - this.tx) / this.scale - this.W / 2, y: (h / 2 - this.ty) / this.scale - this.H / 2 };
  }

  autoArrange(): void {
    layoutGraph({ nodes: this.nodes, edges: this.edges }).then(g => {
      this.nodes = g.nodes; this.cdr.markForCheck(); if (this.viewReady) setTimeout(() => this.fit());
    });
  }

  fit(): void {
    const el = this.host?.nativeElement;
    if (!el || !this.nodes.length) return;
    const xs = this.nodes.map(n => n.x), ys = this.nodes.map(n => n.y);
    const minX = Math.min(...xs), minY = Math.min(...ys);
    const maxX = Math.max(...xs) + this.W, maxY = Math.max(...ys) + this.H + 18;
    const gw = maxX - minX, gh = maxY - minY, pad = 28;
    const s = Math.min((el.clientWidth - pad * 2) / gw, (el.clientHeight - pad * 2) / gh, 1.2);
    this.scale = s > 0 ? s : 1;
    this.tx = (el.clientWidth - gw * this.scale) / 2 - minX * this.scale;
    this.ty = Math.max(pad, (el.clientHeight - gh * this.scale) / 2 - minY * this.scale);
    this.cdr.markForCheck();
  }

  zoomBy(f: number): void {
    const el = this.host?.nativeElement;
    this.zoomAround((el?.clientWidth ?? 0) / 2, (el?.clientHeight ?? 0) / 2, f);
  }
  onWheel(ev: WheelEvent): void {
    ev.preventDefault();
    const r = (ev.currentTarget as HTMLElement).getBoundingClientRect();
    this.zoomAround(ev.clientX - r.left, ev.clientY - r.top, ev.deltaY < 0 ? 1.1 : 0.9);
  }
  private zoomAround(px: number, py: number, f: number): void {
    const next = Math.min(2.5, Math.max(0.15, this.scale * f)), k = next / this.scale;
    this.tx = px - (px - this.tx) * k; this.ty = py - (py - this.ty) * k; this.scale = next;
    this.cdr.markForCheck();
  }
}
