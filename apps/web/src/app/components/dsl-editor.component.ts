import {
  Component, ElementRef, ViewChild, forwardRef,
  Input, OnChanges, AfterViewInit, ChangeDetectionStrategy, ChangeDetectorRef,
} from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-dsl-editor',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  providers: [
    { provide: NG_VALUE_ACCESSOR, useExisting: forwardRef(() => DslEditorComponent), multi: true },
  ],
  template: `
    <div class="dsl-editor" [style.--rows]="rows">
      <div class="gutter" #gutter aria-hidden="true">
        <div class="line-num" *ngFor="let n of lineNums">{{ n }}</div>
      </div>
      <textarea
        #ta
        class="dsl-ta"
        spellcheck="false"
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        [value]="value"
        (input)="onInput($event)"
        (scroll)="syncScroll()"
        (keydown.tab)="onTab($event)"
        (blur)="onTouched()"
      ></textarea>
    </div>
  `,
  styles: [`
    :host { display: block; width: 100%; }

    .dsl-editor {
      display: flex;
      border: 1px solid var(--cg-border-strong);
      border-radius: 4px;
      background: var(--cg-surface);
      overflow: hidden;
      font-family: 'JetBrains Mono', 'Fira Code', 'Cascadia Code', monospace;
      font-size: 13px;
      line-height: 1.6;
      min-height: calc(var(--rows, 14) * 1.6em + 16px);
      transition: border-color 0.15s;
      &:focus-within {
        border-color: var(--cg-accent);
        box-shadow: 0 0 0 3px var(--cg-accent-soft);
      }
    }

    .gutter {
      min-width: 40px;
      padding: 8px 0;
      text-align: right;
      user-select: none;
      overflow: hidden;
      background: var(--cg-surface-2);
      border-right: 1px solid var(--cg-border);
      flex-shrink: 0;
    }

    .line-num {
      padding: 0 8px;
      color: var(--cg-text-muted);
      font-size: 12px;
      line-height: 1.6;
      white-space: pre;
    }

    .dsl-ta {
      flex: 1;
      resize: none;
      border: none;
      outline: none;
      background: transparent;
      color: var(--cg-text);
      padding: 8px 12px;
      line-height: 1.6;
      font-family: inherit;
      font-size: inherit;
      white-space: pre;
      overflow-wrap: normal;
      overflow-x: auto;
      min-height: calc(var(--rows, 14) * 1.6em);
    }
  `],
})
export class DslEditorComponent implements ControlValueAccessor, OnChanges, AfterViewInit {
  @Input() rows = 14;
  @ViewChild('ta')     taRef!:     ElementRef<HTMLTextAreaElement>;
  @ViewChild('gutter') gutterRef!: ElementRef<HTMLDivElement>;

  value = '';
  lineNums: number[] = [1];

  onChange:  (v: string) => void = () => {};
  onTouched: ()          => void = () => {};

  constructor(private cdr: ChangeDetectorRef) {}

  ngOnChanges(): void { this.rebuildLines(); }
  ngAfterViewInit(): void { this.syncScroll(); }

  // ControlValueAccessor
  writeValue(v: string): void {
    this.value = v ?? '';
    this.rebuildLines();
    // Push value into the native textarea if already rendered
    if (this.taRef) this.taRef.nativeElement.value = this.value;
    this.cdr.markForCheck();
  }

  registerOnChange(fn: (v: string) => void):  void { this.onChange  = fn; }
  registerOnTouched(fn: () => void):          void { this.onTouched = fn; }
  setDisabledState(disabled: boolean):        void {
    if (this.taRef) this.taRef.nativeElement.disabled = disabled;
  }

  onInput(event: Event): void {
    this.value = (event.target as HTMLTextAreaElement).value;
    this.rebuildLines();
    this.onChange(this.value);
    this.cdr.markForCheck();
  }

  syncScroll(): void {
    if (this.taRef && this.gutterRef) {
      this.gutterRef.nativeElement.scrollTop = this.taRef.nativeElement.scrollTop;
    }
  }

  // Insert two spaces on Tab instead of losing focus
  onTab(event: Event): void {
    const e = event as KeyboardEvent;
    e.preventDefault();
    const ta = this.taRef.nativeElement;
    const start = ta.selectionStart;
    const end   = ta.selectionEnd;
    const newVal = ta.value.slice(0, start) + '  ' + ta.value.slice(end);
    ta.value = newVal;
    ta.selectionStart = ta.selectionEnd = start + 2;
    this.value = newVal;
    this.rebuildLines();
    this.onChange(newVal);
    this.cdr.markForCheck();
  }

  private rebuildLines(): void {
    const count = (this.value.split('\n').length) || 1;
    if (this.lineNums.length !== count) {
      this.lineNums = Array.from({ length: count }, (_, i) => i + 1);
    }
  }
}
