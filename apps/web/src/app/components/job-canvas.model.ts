/**
 * DSL ↔ tree round-trip shared by the visual job canvas.
 *
 *   • `parseDsl` — a small hand-written recursive-descent scanner that turns DSL
 *     text into a tree. It understands nested `if/else` (brace counting), so the
 *     canvas never silently drops branches.
 *   • `emitDsl`  — renders a tree back to DSL with faithful indentation. `if`
 *     blocks carry no trailing comma (the parser's grammar rejects it); steps and
 *     `use` refs do.
 *
 * The free-canvas graph editor (`job-graph.model.ts`) reuses both: it parses the
 * DSL into this tree, walks it into a node-link graph, and emits structured DSL
 * back out via `emitDsl`.
 */

// ── Editable tree ──────────────────────────────────────────────────────────────

export type CParam = { key: string; value: string };

export interface CStep { id: string; kind: 'step'; name: string; params: CParam[]; }
export interface CUse  { id: string; kind: 'use'; ref: string; }
export interface CIf   { id: string; kind: 'if'; condition: string; then: CNode[]; else: CNode[]; }
export type CNode = CStep | CUse | CIf;

let _uid = 0;
export const newId = (): string => `cn${++_uid}`;

// ── Emit: tree → DSL ────────────────────────────────────────────────────────────

export function emitDsl(taskName: string, nodes: CNode[]): string {
  const body = emitNodes(nodes, 1);
  return `${taskName || 'myPipeline'} {\n${body}\n}`;
}

function emitNodes(nodes: CNode[], depth: number): string {
  return nodes.map(n => emitNode(n, depth)).join('\n');
}

function emitNode(n: CNode, depth: number): string {
  const pad = '  '.repeat(depth);

  if (n.kind === 'use') return `${pad}use "${n.ref || 'job-code'}",`;

  if (n.kind === 'step') {
    const ps = n.params.filter(p => p.key.trim());
    if (!ps.length) return `${pad}step "${n.name || 'stepName'}",`;
    const inner = ps.map(p => `${pad}  ${p.key} ${fmtVal(p.value)}`).join('\n');
    return `${pad}step "${n.name || 'stepName'}" {\n${inner}\n${pad}},`;
  }

  // if/else — no trailing comma: the parser's node grammar rejects it.
  const thenB = n.then.length ? emitNodes(n.then, depth + 1) : `${pad}  // (vazio)`;
  let s = `${pad}if ${n.condition || 'state["key"] > 0'} {\n${thenB}\n${pad}}`;
  if (n.else.length) s += ` else {\n${emitNodes(n.else, depth + 1)}\n${pad}}`;
  return s;
}

/** Numbers/booleans are emitted bare; everything else is quoted. */
function fmtVal(v: string): string {
  if (/^-?\d+(\.\d+)?$/.test(v) || v === 'true' || v === 'false') return v;
  return `"${v.replace(/"/g, '\\"')}"`;
}

// ── Parse: DSL → tree (lenient recursive descent) ───────────────────────────────

export interface ParsedDsl { taskName: string; nodes: CNode[]; }

export function parseDsl(src: string): ParsedDsl {
  const sc = new Scanner(src || '');
  sc.ws();
  const taskName = sc.ident() || 'myPipeline';
  sc.ws();
  sc.expect('{');
  const nodes = sc.nodes();
  sc.ws();
  sc.expect('}');
  return { taskName, nodes };
}

class Scanner {
  i = 0;
  constructor(private s: string) {}

  private eof(): boolean { return this.i >= this.s.length; }
  private cur(): string { return this.s[this.i]; }

  /** Skips whitespace and `//` line comments. */
  ws(): void {
    while (!this.eof()) {
      const c = this.cur();
      if (c === ' ' || c === '\t' || c === '\r' || c === '\n') { this.i++; continue; }
      if (c === '/' && this.s[this.i + 1] === '/') {
        while (!this.eof() && this.cur() !== '\n') this.i++;
        continue;
      }
      break;
    }
  }

  /** Consumes `ch` if present (lenient — a missing brace doesn't throw). */
  expect(ch: string): void {
    this.ws();
    if (this.cur() === ch) this.i++;
  }

  /** True if `kw` is next as a whole word (not a prefix of a longer ident). */
  private keyword(kw: string): boolean {
    this.ws();
    if (!this.s.startsWith(kw, this.i)) return false;
    const after = this.s[this.i + kw.length];
    return after === undefined || !/[A-Za-z0-9_]/.test(after);
  }

  private take(kw: string): void { this.i += kw.length; }

  ident(): string {
    this.ws();
    const m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(this.s.slice(this.i));
    if (!m) return '';
    this.i += m[0].length;
    return m[0];
  }

  /** A quoted/number/bool value, returned as its string content. */
  value(): string {
    this.ws();
    const c = this.cur();
    if (c === '"' || c === "'") return this.quoted(c);
    const m = /^(-?\d+(?:\.\d+)?|true|false)/.exec(this.s.slice(this.i));
    if (m) { this.i += m[0].length; return m[0]; }
    return '';
  }

  private quoted(q: string): string {
    this.i++; // opening quote
    let out = '';
    while (!this.eof() && this.cur() !== q) {
      if (this.cur() === '\\' && this.s[this.i + 1] !== undefined) {
        const n = this.s[this.i + 1];
        out += n === 'n' ? '\n' : n === 't' ? '\t' : n;
        this.i += 2;
      } else {
        out += this.cur();
        this.i++;
      }
    }
    this.i++; // closing quote
    return out;
  }

  /** Parses a sequence of nodes until a closing `}` or EOF. */
  nodes(): CNode[] {
    const out: CNode[] = [];
    while (true) {
      this.ws();
      if (this.eof() || this.cur() === '}') break;

      const before = this.i;
      const n = this.node();
      if (n) out.push(n);

      this.ws();
      if (this.cur() === ',') this.i++; // optional separator
      if (this.i === before) this.i++;  // guard against stalls on junk
    }
    return out;
  }

  private node(): CNode | null {
    if (this.keyword('if')) return this.ifNode();
    if (this.keyword('use')) { this.take('use'); return { id: newId(), kind: 'use', ref: this.value() }; }
    if (this.keyword('job')) { this.take('job'); return { id: newId(), kind: 'use', ref: this.value() }; }
    if (this.keyword('step')) return this.stepNode();
    return null;
  }

  private stepNode(): CStep {
    this.take('step');
    const name = this.value();
    this.ws();
    if (this.cur() === ',') this.i++;
    this.ws();
    const params: CParam[] = [];
    if (this.cur() === '{') {
      this.i++;
      while (true) {
        this.ws();
        if (this.eof() || this.cur() === '}') break;
        const key = this.ident();
        if (!key) { this.i++; continue; }
        const value = this.value();
        params.push({ key, value });
        this.ws();
        if (this.cur() === ',') this.i++;
      }
      this.expect('}');
    }
    return { id: newId(), kind: 'step', name, params };
  }

  private ifNode(): CIf {
    this.take('if');
    // Condition is raw text up to the block opener; conditions never contain `{`.
    const start = this.i;
    while (!this.eof() && this.cur() !== '{') this.i++;
    const condition = this.s.slice(start, this.i).trim();
    this.expect('{');
    const thenNodes = this.nodes();
    this.expect('}');
    let elseNodes: CNode[] = [];
    if (this.keyword('else')) {
      this.take('else');
      this.expect('{');
      elseNodes = this.nodes();
      this.expect('}');
    }
    return { id: newId(), kind: 'if', condition, then: thenNodes, else: elseNodes };
  }
}
