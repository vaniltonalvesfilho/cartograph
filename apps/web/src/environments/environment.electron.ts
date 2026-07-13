// Electron (desktop) environment. The app is served from the custom `app://`
// protocol, so there is no HTTP origin to derive same-origin URLs from — the
// backend address is injected at runtime by the Electron preload script, which
// exposes `window.cartograph.config` before this module is evaluated. If the
// bridge is absent (e.g. a stray browser load), we fall back to localhost.
// The `window.cartograph` type is declared in electron.service.ts.
const cfg = (typeof window !== 'undefined' && window.cartograph?.config) || {
  apiBase: 'http://localhost:8080/api',
  graphqlHttp: 'http://localhost:8080/graphql',
  socketUrl: 'ws://localhost:8080/socket',
};

export const environment = {
  production: true,
  // Hash routing is required: PathLocationStrategy breaks under app:// / file://.
  useHash: true,
  apiBase: cfg.apiBase,
  graphqlHttp: cfg.graphqlHttp,
  socketUrl: cfg.socketUrl,
};
