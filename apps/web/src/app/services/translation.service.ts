import { Injectable, signal } from '@angular/core';
import { PT } from './i18n/pt';
import { EN } from './i18n/en';

export type Lang = 'pt' | 'en';

export interface LangOption {
  code: Lang;
  label: string;
  flag: string;
}

export const LANGUAGES: LangOption[] = [
  { code: 'pt', label: 'Português', flag: '🇧🇷' },
  { code: 'en', label: 'English', flag: '🇺🇸' },
];

// Flat translation dictionary. Keys are dot-namespaced by area. Portuguese is
// the source/fallback language; English mirrors it. Use {param} placeholders
// for interpolation (see TranslationService.t).
const DICT: Record<Lang, Record<string, string>> = { pt: PT, en: EN };

@Injectable({ providedIn: 'root' })
export class TranslationService {
  private readonly KEY = 'cartograph-lang';

  /** Current language as a signal so template bindings react to changes. */
  readonly lang = signal<Lang>(this.initial());

  readonly languages = LANGUAGES;

  constructor() {
    document.documentElement.lang = this.lang();
  }

  setLang(code: Lang): void {
    this.lang.set(code);
    localStorage.setItem(this.KEY, code);
    document.documentElement.lang = code;
  }

  /** Translates a key, interpolating {param} placeholders. Falls back to pt, then the key itself. */
  t(key: string, params?: Record<string, string | number | null | undefined>): string {
    const lang = this.lang();
    let str = DICT[lang]?.[key] ?? DICT.pt[key] ?? key;
    if (params) {
      for (const p of Object.keys(params)) {
        str = str.replace(new RegExp(`\\{${p}\\}`, 'g'), String(params[p] ?? ''));
      }
    }
    return str;
  }

  private initial(): Lang {
    const saved = localStorage.getItem(this.KEY);
    if (saved === 'pt' || saved === 'en') return saved;
    return navigator.language?.toLowerCase().startsWith('en') ? 'en' : 'pt';
  }
}
