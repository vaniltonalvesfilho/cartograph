import { Pipe, PipeTransform, inject } from '@angular/core';
import { TranslationService } from './translation.service';

/**
 * Usage: {{ 'settings.title' | translate }} or {{ 'msg.key' | translate:{ name: x } }}.
 *
 * Impure so it re-evaluates when the active language changes (the service reads
 * a signal, but pipe instances aren't re-created on signal change on their own).
 */
@Pipe({ name: 'translate', standalone: true, pure: false })
export class TranslatePipe implements PipeTransform {
  private readonly ts = inject(TranslationService);

  transform(key: string, params?: Record<string, string | number | null | undefined>): string {
    return this.ts.t(key, params);
  }
}
