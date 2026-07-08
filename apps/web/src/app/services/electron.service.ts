import { Injectable } from '@angular/core';

// Shape of the bridge the Electron preload exposes. Declared here (always
// compiled) so both the web and electron builds see the type.
declare global {
  interface Window {
    cartograph?: {
      config: { apiBase: string; graphqlHttp: string; socketUrl: string };
      getServerUrl: () => Promise<string>;
      setServerUrl: (url: string) => Promise<void>;
    };
  }
}

// Thin wrapper over the `window.cartograph` bridge exposed by the Electron
// preload script. In a plain browser build the bridge is absent, so `isElectron`
// is false and the desktop-only UI stays hidden.
@Injectable({ providedIn: 'root' })
export class ElectronService {
  get isElectron(): boolean {
    return typeof window !== 'undefined' && !!window.cartograph;
  }

  /** Current backend base URL (e.g. http://localhost:8080), or '' outside Electron. */
  async getServerUrl(): Promise<string> {
    return this.isElectron ? window.cartograph!.getServerUrl() : '';
  }

  /** Persist a new backend URL; the main process reloads the window afterwards. */
  async setServerUrl(url: string): Promise<void> {
    if (this.isElectron) await window.cartograph!.setServerUrl(url);
  }
}
