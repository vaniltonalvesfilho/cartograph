import {
  Directive, ElementRef, HostListener, Input, OnDestroy,
} from '@angular/core';
import { Overlay, OverlayRef } from '@angular/cdk/overlay';
import { ComponentPortal } from '@angular/cdk/portal';
import {
  Component, ChangeDetectionStrategy, Input as CInput,
} from '@angular/core';

type TipPos = 'above' | 'below' | 'before' | 'after';

@Component({
  selector: 'cg-tooltip-box',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `{{ text }}`,
  styles: [`
    :host {
      display: block;
      max-width: 240px;
      background: var(--cg-tooltip-bg, #18181b);
      color: var(--cg-tooltip-fg, #fafafa);
      font-size: 12px;
      font-weight: 500;
      line-height: 1.4;
      padding: 5px 9px;
      border-radius: 6px;
      box-shadow: var(--cg-shadow-md, 0 4px 12px rgba(0,0,0,.2));
      pointer-events: none;
      white-space: nowrap;
    }
  `],
})
export class TooltipBoxComponent {
  @CInput() text = '';
}

/**
 * Lightweight tooltip directive (CDK overlay, no @angular/material).
 * Drop-in replacement for matTooltip: [cgTooltip]="text" + cgTooltipPos.
 */
@Directive({
  selector: '[cgTooltip]',
  standalone: true,
})
export class TooltipDirective implements OnDestroy {
  @Input('cgTooltip') text = '';
  @Input('cgTooltipPos') pos: TipPos = 'below';
  @Input() cgTooltipDisabled = false;

  private ref?: OverlayRef;
  private timer?: ReturnType<typeof setTimeout>;

  constructor(private host: ElementRef<HTMLElement>, private overlay: Overlay) {}

  @HostListener('mouseenter')
  @HostListener('focus')
  show(): void {
    if (!this.text || this.cgTooltipDisabled || this.ref) return;
    this.timer = setTimeout(() => this.create(), 350);
  }

  @HostListener('mouseleave')
  @HostListener('blur')
  @HostListener('click')
  hide(): void {
    clearTimeout(this.timer);
    this.ref?.dispose();
    this.ref = undefined;
  }

  private create(): void {
    const positions = this.positionsFor(this.pos);
    const positionStrategy = this.overlay
      .position()
      .flexibleConnectedTo(this.host)
      .withPositions(positions)
      .withPush(true);

    this.ref = this.overlay.create({
      positionStrategy,
      scrollStrategy: this.overlay.scrollStrategies.close(),
    });
    const portal = new ComponentPortal(TooltipBoxComponent);
    const cmp = this.ref.attach(portal);
    cmp.instance.text = this.text;
  }

  private positionsFor(pos: TipPos) {
    const gap = 8;
    switch (pos) {
      case 'above':
        return [{ originX: 'center', originY: 'top', overlayX: 'center', overlayY: 'bottom', offsetY: -gap } as const];
      case 'before':
        return [{ originX: 'start', originY: 'center', overlayX: 'end', overlayY: 'center', offsetX: -gap } as const];
      case 'after':
        return [{ originX: 'end', originY: 'center', overlayX: 'start', overlayY: 'center', offsetX: gap } as const];
      case 'below':
      default:
        return [{ originX: 'center', originY: 'bottom', overlayX: 'center', overlayY: 'top', offsetY: gap } as const];
    }
  }

  ngOnDestroy(): void { this.hide(); }
}
