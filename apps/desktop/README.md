# Cartograph Desktop

Electron wrapper around the Angular dashboard (`apps/web`). It ships the built
SPA and connects to a Cartograph backend as a **client of a service** — the
server address is configurable at runtime from a Settings screen.

## How it works

- The Angular app is built with a dedicated config (`ng build --configuration
  electron`) that enables **hash routing**, sets `<base href="./">`, and reads
  the backend URLs from `window.cartograph.config` (see
  `apps/web/src/environments/environment.electron.ts`).
- Electron serves the build over a custom **`app://cartograph`** protocol — a
  stable origin whitelisted in the backend (`Corsica` origins and the socket
  `check_origin`), so REST, GraphQL and the Phoenix WebSocket all work.
- `electron/preload.js` injects the derived config (from the persisted server
  URL) and exposes `getServerUrl` / `setServerUrl`. Changing the server persists
  it (`userData/config.json`) and reloads the window.

## Develop

```bash
# from repo root — backend must be running (make backend), then:
make desktop            # builds apps/web (electron config) and opens the app
# or:
cd apps/desktop && npm install && npm run dev
```

To point the renderer at a live `ng serve` instead of the bundled build:

```bash
ELECTRON_RENDERER_URL=http://localhost:4200 npm start
```

## Package (Linux)

```bash
make desktop.build      # → apps/desktop/dist/*.AppImage
```

The AppImage is portable and dependency-free — `chmod +x` it and run, or
double-click. To also produce a `.deb`, install `libxcrypt-compat` (fpm's
bundled Ruby needs `libcrypt.so.1`) and add `- deb` back under `linux.target`
in `electron-builder.yml`.

## Change the server address

Open the **Server address** entry (on the login screen, or the user menu once
signed in) and enter the backend URL, e.g. `http://localhost:8080`. The app
reconnects on save.
