import { Injectable, inject } from '@angular/core';
import { Observable, Subscriber } from 'rxjs';
import { Socket, Channel } from 'phoenix';
import { DocumentNode, print } from 'graphql';
import { AuthService } from './auth.service';
import { environment } from '../../environments/environment';

/**
 * GraphQL subscriptions over the Phoenix channel transport.
 *
 * The backend serves subscriptions through `Absinthe.Phoenix` (UserSocket →
 * `__absinthe__:control` channel), NOT the graphql-ws protocol — so Apollo's
 * websocket links cannot talk to it. This service speaks the Absinthe wire
 * protocol directly:
 *
 *   join "__absinthe__:control"
 *   push "doc" {query, variables}      → reply {subscriptionId}
 *   receive event "subscription:data"  → payload {subscriptionId, result: {data}}
 *   push "unsubscribe" {subscriptionId}
 *
 * The socket authenticates with the same bearer token as REST (UserSocket
 * verifies it in `connect/3` and refuses anonymous connections). Queries and
 * mutations stay on Apollo over HTTP.
 */
@Injectable({ providedIn: 'root' })
export class AbsintheSocketService {
  private readonly auth = inject(AuthService);

  private socket?: Socket;
  private channel?: Channel;
  private everOpened = false;

  /** Active docs by subscriptionId — fan-out to observers, re-push on reconnect. */
  private active = new Map<string, { query: string; variables: unknown; observers: Set<Subscriber<unknown>> }>();

  /** Subscribes to a GraphQL subscription document; emits each result's `data`. */
  subscribe<T>(query: DocumentNode, variables: Record<string, unknown>): Observable<T> {
    const doc = print(query);

    return new Observable<T>((observer) => {
      const channel = this.ensureChannel();
      let subscriptionId: string | undefined;

      channel
        .push('doc', { query: doc, variables })
        .receive('ok', (reply: { subscriptionId: string }) => {
          subscriptionId = reply.subscriptionId;

          // Torn down before the reply landed: don't register the dead
          // observer, and release the server-side doc if nobody else uses it.
          if ((observer as Subscriber<unknown>).closed) {
            const orphan = this.active.get(subscriptionId);
            if (!orphan || orphan.observers.size === 0) {
              this.active.delete(subscriptionId);
              this.channel?.push('unsubscribe', { subscriptionId });
            }
            return;
          }

          const entry = this.active.get(subscriptionId) ??
            { query: doc, variables, observers: new Set<Subscriber<unknown>>() };
          entry.observers.add(observer as Subscriber<unknown>);
          this.active.set(subscriptionId, entry);
        })
        .receive('error', (err: unknown) => observer.error(err))
        .receive('timeout', () => observer.error(new Error('subscription join timeout')));

      return () => {
        if (!subscriptionId) return;
        const entry = this.active.get(subscriptionId);
        if (!entry) return;
        entry.observers.delete(observer as Subscriber<unknown>);
        if (entry.observers.size === 0) {
          this.active.delete(subscriptionId);
          this.channel?.push('unsubscribe', { subscriptionId });
        }
      };
    });
  }

  private ensureChannel(): Channel {
    if (this.channel) return this.channel;

    // Token as a closure so reconnects after a re-login pick up the fresh one.
    this.socket = new Socket(environment.socketUrl, {
      params: () => ({ token: this.auth.token ?? '' }),
    });

    // Absinthe broadcasts results as bare socket messages on the subscription's
    // own topic — no phoenix.js channel exists for it, so tap the socket.
    this.socket.onMessage((message: object) => {
      const msg = message as { topic: string; event: string; payload: unknown };
      if (msg.event !== 'subscription:data') return;
      const payload = msg.payload as { subscriptionId: string; result: { data: unknown } };
      const entry = this.active.get(payload.subscriptionId);
      if (entry) entry.observers.forEach((o) => o.next(payload.result?.data));
    });

    // Server-side subscriptions die with the connection: re-register the active
    // docs on every reconnect (skip the very first open — those pushes are
    // already buffered by phoenix.js).
    this.socket.onOpen(() => {
      if (!this.everOpened) { this.everOpened = true; return; }
      const previous = [...this.active.values()];
      this.active.clear();
      for (const entry of previous) {
        this.channel!
          .push('doc', { query: entry.query, variables: entry.variables })
          .receive('ok', (reply: { subscriptionId: string }) => {
            const existing = this.active.get(reply.subscriptionId);
            if (existing) {
              entry.observers.forEach((o) => existing.observers.add(o));
            } else {
              this.active.set(reply.subscriptionId, entry);
            }
          });
      }
    });

    this.socket.connect();
    this.channel = this.socket.channel('__absinthe__:control');
    this.channel.join();
    return this.channel;
  }
}
