import { ChangeDetectionStrategy, Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';

// GitLab-like palette for deterministic avatars
const PALETTE = [
  '#e2685f', '#e9803f', '#dca513', '#5a9e4b',
  '#3aa39a', '#4a8ee8', '#7c6fdb', '#c065c0',
  '#d65a8a', '#5b7a9e',
];

@Component({
  selector: 'app-ident-icon',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CommonModule],
  template: `
    <span class="ident"
          [style.width.px]="size"
          [style.height.px]="size"
          [style.font-size.px]="size * 0.42"
          [style.border-radius.px]="size * 0.25"
          [style.background]="bg">
      {{ initials }}
    </span>
  `,
})
export class IdentIconComponent {
  @Input() name = '';
  @Input() size = 32;

  get initials(): string {
    const words = this.name.trim().split(/[\s_-]+/).filter(Boolean);
    if (words.length === 0) return '?';
    if (words.length === 1) return words[0].slice(0, 2);
    return (words[0][0] + words[1][0]);
  }

  get bg(): string {
    let hash = 0;
    for (let i = 0; i < this.name.length; i++) {
      hash = (hash * 31 + this.name.charCodeAt(i)) >>> 0;
    }
    return PALETTE[hash % PALETTE.length];
  }
}
