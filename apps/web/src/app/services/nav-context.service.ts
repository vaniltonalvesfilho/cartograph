import { Injectable } from '@angular/core';
import { BehaviorSubject } from 'rxjs';

export interface Crumb {
  label: string;
  link?: any[];   // routerLink; absent = current item (not clickable)
}

/**
 * Keeps the breadcrumb trail of the current context.
 * Each page (dashboard, group, project, execution) calls `set()` in ngOnInit
 * with the appropriate trail — analogous to GitLab's contextual breadcrumb.
 */
@Injectable({ providedIn: 'root' })
export class NavContextService {
  private readonly trail$ = new BehaviorSubject<Crumb[]>([]);
  readonly crumbs = this.trail$.asObservable();

  set(crumbs: Crumb[]): void {
    this.trail$.next(crumbs);
  }
}
