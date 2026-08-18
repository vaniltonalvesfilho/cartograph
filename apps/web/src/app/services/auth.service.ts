import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { tap, map, catchError } from 'rxjs/operators';
import { User } from '../models';
import { environment } from '../../environments/environment';

const BASE = environment.apiBase;
const TOKEN_KEY = 'cartograph-token';

export interface LoginResult {
  requireTotp: boolean;
  pendingToken?: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private userSubject = new BehaviorSubject<User | null>(null);
  readonly currentUser$ = this.userSubject.asObservable();

  constructor(private http: HttpClient, private router: Router) {}

  get currentUser(): User | null { return this.userSubject.value; }
  get token(): string | null { return localStorage.getItem(TOKEN_KEY); }
  get isAuthenticated(): boolean { return !!this.token; }
  get isAdmin(): boolean { return this.userSubject.value?.isAdmin === true; }

  login(email: string, password: string): Observable<LoginResult> {
    return this.http.post<any>(`${BASE}/auth/login`, { email, password }).pipe(
      map(res => {
        if (res.status === 'totp_required') {
          return { requireTotp: true, pendingToken: res.pendingToken };
        }
        localStorage.setItem(TOKEN_KEY, res.token);
        this.userSubject.next(res.user);
        return { requireTotp: false };
      }),
    );
  }

  verifyTotpLogin(pendingToken: string, code: string): Observable<void> {
    return this.http.post<any>(`${BASE}/auth/2fa/verify`, { pendingToken, code }).pipe(
      tap(res => {
        localStorage.setItem(TOKEN_KEY, res.token);
        this.userSubject.next(res.user);
      }),
      map(() => void 0),
    );
  }

  /**
   * Signs out. The server session is revoked first — dropping the token
   * locally used to leave it valid for weeks to anyone who had a copy.
   */
  logout(): void {
    if (this.token) {
      // Fire and forget: the local session is cleared either way.
      this.http.post(`${BASE}/auth/logout`, {}).subscribe({ error: () => {} });
    }
    this.clearSession();
  }

  /** Forgets the session locally, without calling the server. */
  private clearSession(): void {
    localStorage.removeItem(TOKEN_KEY);
    this.userSubject.next(null);
    this.router.navigate(['/login']);
  }

  patchCurrentUser(patch: Partial<import('../models').User>): void {
    const u = this.userSubject.value;
    if (u) this.userSubject.next({ ...u, ...patch });
  }

  restoreSession(): Observable<boolean> {
    if (!this.token) return of(false);
    return this.http.get<User>(`${BASE}/auth/me`).pipe(
      tap(user => this.userSubject.next(user)),
      map(() => true),
      // The token was already refused, so there is no session left to revoke.
      catchError(() => { this.clearSession(); return of(false); }),
    );
  }
}
