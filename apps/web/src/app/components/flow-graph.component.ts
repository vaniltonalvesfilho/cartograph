import {
  AfterViewInit, ChangeDetectionStrategy, ChangeDetectorRef, Component,
  ElementRef, EventEmitter, Input, OnChanges, Output, SimpleChanges, ViewChild,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { IconComponent } from './icon.component';
import { TooltipDirective } from './ui/tooltip.directive';
import { TranslatePipe } from '../services/translate.pipe';
import { FlowNode, Status } from '../models';
import { FlowGraph, GNode, layoutFlow } from './flow-graph.model';

/**
 * Modern SVG renderer for a job's execution flow as a node-link graph. Sub-jobs
 * and if-branches are nested compound boxes; ELK does the layout. Pure SVG (no
 * foreignObject) so it themes via CSS vars and renders reliably. Pan with drag,
 * zoom with the wheel; nodes carry a stable id for later live-execution overlay.
 */
@Component({
  selector: 'app-flow-graph',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule, IconComponent, TooltipDirective, TranslatePipe],
  template: `
    <div class="graph-host" #host
         (wheel)="onWheel($event)"
         (pointerdown)="onDown($event)"
         (pointermove)="onMove($event)"
         (pointerup)="onUp()"
         (pointerleave)="onUp()">

      <div class="toolbar">
        <button class="cg-icon-btn" (click)="fit()" [cgTooltip]="'flow.fit' | translate"><app-icon>fit_screen</app-icon></button>
        <button class="cg-icon-btn" (click)="zoomBy(1.2)" [cgTooltip]="'flow.zoomIn' | translate"><app-icon>add</app-icon></button>
        <button class="cg-icon-btn" (click)="zoomBy(0.83)" [cgTooltip]="'flow.zoomOut' | translate"><app-icon>remove</app-icon></button>
      </div>

      <div *ngIf="loading" class="g-loading"><span class="cg-spinner"></span></div>

      <svg *ngIf="graph && !loading" class="canvas" [class.dragging]="dragging">
        <defs>
          <marker id="fg-arrow" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto">
            <path d="M0,0 L7,3.5 L0,7 z" class="arrow"></path>
          </marker>
        </defs>
        <g [attr.transform]="'translate(' + tx + ',' + ty + ') scale(' + scale + ')'">
          <path *ngFor="let e of graph.edges" class="edge" [attr.d]="pathOf(e.points)" marker-end="url(#fg-arrow)"></path>

          <g *ngFor="let n of graph.nodes" [attr.transform]="'translate(' + n.x + ',' + n.y + ')'"
             class="node" [ngClass]="nodeClasses(n)">
            <rect class="box" [attr.width]="n.w" [attr.height]="n.h" rx="10" ry="10"></rect>

            <!-- Container header strip (job / if / branch) -->
            <ng-container *ngIf="n.container">
              <rect class="hdr" [attr.width]="n.w" height="28" rx="10" ry="10"></rect>
              <text class="hdr-title" x="12" y="18">{{ headerLabel(n) }}</text>
              <text *ngIf="n.kind === 'job' && n.sub" class="hdr-sub mono" [attr.x]="n.w - 12" y="18"
                    text-anchor="end">{{ trunc(n.sub, n.w - labelW(headerLabel(n)) - 40, 6.5) }}</text>
              <g *ngIf="n.kind === 'job' && n.cycle" class="cycle"><text [attr.x]="n.w - 12" y="18" text-anchor="end">↻</text></g>
            </ng-container>

            <!-- Leaf (step / job_error) -->
            <ng-container *ngIf="!n.container">
              <text class="title" x="14" [attr.y]="n.sub ? 22 : 30">{{ trunc(n.title, n.w - 28, 7.2) }}</text>
              <text *ngIf="n.sub" class="sub mono" x="14" y="40">{{ trunc(n.sub, n.w - 28, 6.6) }}</text>
              <text *ngIf="isAgent(n)" class="agent-glyph" [attr.x]="n.w - 13" y="19" text-anchor="end">✦</text>
            </ng-container>

            <!-- Clickable open for sub-jobs -->
            <rect *ngIf="n.kind === 'job' && n.taskId" class="hit" [attr.width]="n.w" height="28"
                  (click)="open(n)"></rect>

            <!-- Clickable step (live-execution overlay: select → filter logs) -->
            <rect *ngIf="selectable && n.kind === 'step'" class="hit-step" [attr.width]="n.w"
                  [attr.height]="n.h" rx="10" ry="10" (click)="onStepClick(n)"></rect>
          </g>
        </g>
      </svg>
    </div>
  `,
  styles: [`
    .graph-host {
      position: relative;
      width: 100%;
      height: 520px;
      overflow: hidden;
      border-radius: 10px;
      background:
        radial-gradient(circle at 1px 1px, var(--cg-border, rgba(127,127,127,0.25)) 1px, transparent 0);
      background-size: 22px 22px;
      border: 1px solid var(--cg-border, rgba(127,127,127,0.2));
      touch-action: none;
    }
    .toolbar {
      position: absolute; top: 8px; right: 8px; z-index: 2;
      display: flex; gap: 2px;
      background: var(--cg-surface-2, rgba(127,127,127,0.12));
      border: 1px solid var(--cg-border, rgba(127,127,127,0.2));
      border-radius: 8px; padding: 2px;
    }
    .toolbar button { width: 32px; height: 32px; line-height: 32px; }
    .g-loading { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }
    .canvas { width: 100%; height: 100%; cursor: grab; display: block; }
    .canvas.dragging { cursor: grabbing; }

    .edge { fill: none; stroke: var(--cg-accent); stroke-width: 1.6; opacity: 0.6; }
    .arrow { fill: var(--cg-accent); opacity: 0.7; }

    .node .box { fill: var(--cg-surface-2, rgba(127,127,127,0.08)); stroke: var(--cg-border, rgba(127,127,127,0.3)); stroke-width: 1; }
    .node .title { fill: var(--cg-text, currentColor); font-weight: 600; font-size: 13.5px; }
    .node .sub { fill: var(--cg-text-muted); font-size: 11.5px; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }

    /* step */
    .k-step .box { stroke: color-mix(in srgb, var(--cg-accent) 45%, var(--cg-border, gray)); }

    /* agent step (differentiated by step name, not a new kind) */
    .is-agent .box {
      fill: color-mix(in srgb, #a855f7 8%, transparent);
      stroke: #a855f7; stroke-width: 1.5;
    }
    .is-agent .agent-glyph { fill: #c084fc; font-size: 14px; font-weight: 700; }

    /* job_error */
    .k-job_error .box { fill: #7f1d1d22; stroke: #f8717188; }
    .k-job_error .title { fill: #f87171; }

    /* job container */
    .k-job .box { fill: color-mix(in srgb, var(--cg-accent) 5%, transparent); stroke: var(--cg-accent); }
    .k-job .hdr { fill: color-mix(in srgb, var(--cg-accent) 16%, transparent); }
    .k-job .hdr-title { fill: var(--cg-text, currentColor); font-weight: 700; font-size: 12px; }
    .k-job .hdr-sub { fill: var(--cg-text-muted); font-size: 11px; }
    .k-job .cycle text { fill: #fbbf24; font-size: 13px; }
    .k-job .hit { fill: transparent; cursor: pointer; }

    /* if container */
    .k-if .box { fill: transparent; stroke: #a855f7aa; stroke-dasharray: 5 4; }
    .k-if .hdr { fill: #a855f71f; }
    .k-if .hdr-title { fill: #c084fc; font-weight: 700; font-size: 12px; }

    /* branch container */
    .k-branch .box { fill: rgba(127,127,127,0.05); stroke: var(--cg-border, rgba(127,127,127,0.25)); }
    .k-branch .hdr { fill: transparent; }
    .k-branch .hdr-title { font-size: 10px; font-weight: 700; letter-spacing: 0.6px; text-transform: uppercase; }
    .node.k-branch .hdr-title { fill: #34d399; }

    /* ── Live-execution overlay (statusByNode) ─────────────────────────────── */
    .hit-step { fill: transparent; cursor: pointer; }

    .s-PENDING .box { stroke: #6b7280; }
    .s-RUNNING .box {
      fill: #2563eb1a; stroke: #3b82f6; stroke-width: 2;
      animation: fg-pulse 1.4s ease-in-out infinite;
    }
    .s-SUCCESS .box { fill: #05966914; stroke: #10b981; }
    .s-FAILED  .box { fill: #dc26261a; stroke: #ef4444; stroke-width: 2; }
    .s-FAILED  .title { fill: #f87171; }
    .s-STOPPED .box { fill: #d977061a; stroke: #f59e0b; }
    .s-SKIPPED .box { opacity: 0.45; }

    .selected .box { stroke: var(--cg-accent); stroke-width: 2.5; }

    @keyframes fg-pulse {
      0%, 100% { stroke-opacity: 1; }
      50%      { stroke-opacity: 0.35; }
    }
  `],
})
export class FlowGraphComponent implements OnChanges, AfterViewInit {
  @Input() flow: FlowNode[] = [];
  /** Live-execution overlay: step status per Dsl.Flow node id (flowNodeId). */
  @Input() statusByNode: Record<string, Status> | null = null;
  /** When true, step nodes are clickable and emit `stepClick`. */
  @Input() selectable = false;
  /** Node id to highlight as selected (controlled by the parent). */
  @Input() selectedId: string | null = null;

  @Output() stepClick = new EventEmitter<GNode>();

  @ViewChild('host') host?: ElementRef<HTMLElement>;

  graph?: FlowGraph;
  loading = true;
  scale = 1;
  tx = 0;
  ty = 0;
  dragging = false;

  private lastX = 0;
  private lastY = 0;
  private viewReady = false;

  constructor(private cdr: ChangeDetectorRef, private router: Router) {}

  ngAfterViewInit(): void {
    this.viewReady = true;
    if (this.graph) this.fit();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['flow']) this.relayout();
  }

  private relayout(): void {
    this.loading = true;
    layoutFlow(this.flow || []).then(g => {
      this.graph = g;
      this.loading = false;
      this.cdr.markForCheck();
      if (this.viewReady) setTimeout(() => this.fit());
    }).catch(() => { this.loading = false; this.cdr.markForCheck(); });
  }

  // ── Rendering helpers ─────────────────────────────────────────────────────────

  nodeClasses(n: GNode): string {
    const status = this.statusByNode?.[n.id];
    return [
      `k-${n.kind}`,
      this.isAgent(n) ? 'is-agent' : '',
      status ? `s-${status}` : '',
      this.selectedId === n.id ? 'selected' : '',
    ].filter(Boolean).join(' ');
  }

  /** Agent steps are differentiated by step name, not a new graph kind. */
  isAgent(n: GNode): boolean {
    return n.kind === 'step' && n.title === 'agent';
  }

  onStepClick(n: GNode): void {
    this.stepClick.emit(n);
  }

  pathOf(points: { x: number; y: number }[]): string {
    if (!points.length) return '';
    return points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ');
  }

  headerLabel(n: GNode): string {
    if (n.kind === 'if') return `if ${n.title}`;
    if (n.kind === 'branch') return n.branch === 'else' ? 'else' : 'then';
    return n.title;
  }

  labelW(text: string): number { return text.length * 6.8; }

  trunc(text: string, maxW: number, charPx: number): string {
    if (!text) return '';
    const max = Math.max(3, Math.floor(maxW / charPx));
    return text.length > max ? text.slice(0, max - 1) + '…' : text;
  }

  open(n: GNode): void {
    if (n.taskId) this.router.navigate(['/tasks', n.taskId]);
  }

  // ── Pan / zoom ────────────────────────────────────────────────────────────────

  fit(): void {
    const el = this.host?.nativeElement;
    if (!el || !this.graph || !this.graph.width) return;
    const pad = 24;
    const hw = el.clientWidth, hh = el.clientHeight;
    const s = Math.min((hw - pad * 2) / this.graph.width, (hh - pad * 2) / this.graph.height, 1.1);
    this.scale = s > 0 ? s : 1;
    this.tx = (hw - this.graph.width * this.scale) / 2;
    this.ty = Math.max(pad, (hh - this.graph.height * this.scale) / 2);
    this.cdr.markForCheck();
  }

  zoomBy(factor: number): void {
    const el = this.host?.nativeElement;
    const cx = (el?.clientWidth ?? 0) / 2;
    const cy = (el?.clientHeight ?? 0) / 2;
    this.zoomAround(cx, cy, factor);
  }

  onWheel(ev: WheelEvent): void {
    ev.preventDefault();
    const rect = (ev.currentTarget as HTMLElement).getBoundingClientRect();
    this.zoomAround(ev.clientX - rect.left, ev.clientY - rect.top, ev.deltaY < 0 ? 1.1 : 0.9);
  }

  private zoomAround(px: number, py: number, factor: number): void {
    const next = Math.min(2.5, Math.max(0.15, this.scale * factor));
    const k = next / this.scale;
    this.tx = px - (px - this.tx) * k;
    this.ty = py - (py - this.ty) * k;
    this.scale = next;
    this.cdr.markForCheck();
  }

  onDown(ev: PointerEvent): void {
    this.dragging = true;
    this.lastX = ev.clientX;
    this.lastY = ev.clientY;
  }

  onMove(ev: PointerEvent): void {
    if (!this.dragging) return;
    this.tx += ev.clientX - this.lastX;
    this.ty += ev.clientY - this.lastY;
    this.lastX = ev.clientX;
    this.lastY = ev.clientY;
    this.cdr.markForCheck();
  }

  onUp(): void { this.dragging = false; }
}
