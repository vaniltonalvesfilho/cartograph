import { Injectable } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class CronHelperService {
  describe(expr: string): string {
    const parts = expr.trim().split(/\s+/);
    if (parts.length !== 5) return 'Invalid expression (use: minute hour day month day-of-week)';

    const [min, hour, dom, month, dow] = parts;

    try {
      const time = this.formatTime(min, hour);
      const freq = this.formatFrequency(dom, month, dow);
      return `${freq}${time}`;
    } catch {
      return 'Invalid cron expression';
    }
  }

  private formatTime(min: string, hour: string): string {
    if (min === '*' || hour === '*') return '';
    const h = parseInt(hour, 10);
    const m = parseInt(min, 10);
    if (isNaN(h) || isNaN(m)) return '';
    return ` at ${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
  }

  private formatFrequency(dom: string, month: string, dow: string): string {
    const dowNames: Record<string, string> = {
      '0': 'Sun', '1': 'Mon', '2': 'Tue', '3': 'Wed',
      '4': 'Thu', '5': 'Fri', '6': 'Sat', '7': 'Sun',
    };

    if (dom === '*' && month === '*' && dow === '*') return 'Every day';
    if (dom === '*' && month === '*' && dow !== '*') {
      if (dow === '1-5') return 'Mon–Fri';
      if (dow === '0,6' || dow === '6,0') return 'Weekends';
      const days = dow.split(',').map(d => dowNames[d] ?? d).join(', ');
      return days;
    }
    if (dom !== '*' && month === '*') return `Every day ${dom} of the month`;
    if (dom !== '*' && month !== '*') return `Day ${dom} of month ${month}`;
    return 'Custom schedule';
  }
}
