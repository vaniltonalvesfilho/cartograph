const { app, BrowserWindow, protocol, net, ipcMain } = require('electron');
const path = require('path');
const { pathToFileURL } = require('url');
const config = require('./config');

// Stable origin for the desktop client — whitelisted in the backend's Corsica
// and socket check_origin. Served from the built Angular assets.
const SCHEME = 'app';
const HOST = 'cartograph';

// Where the `ng build --configuration electron` output lives.
function rendererRoot() {
  return app.isPackaged
    ? path.join(process.resourcesPath, 'web')
    : path.join(__dirname, '..', '..', 'web', 'dist', 'cartograph-electron', 'browser');
}

// Must run before app is ready so the scheme behaves like a secure http origin
// (fetch/CORS enabled) — required for the Apollo/REST/WebSocket calls to work.
protocol.registerSchemesAsPrivileged([
  {
    scheme: SCHEME,
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true },
  },
]);

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      // sandbox off so preload can require ./config (deriveConfig).
      sandbox: false,
    },
  });

  // ELECTRON_RENDERER_URL lets you point at `ng serve` during development.
  const devUrl = process.env.ELECTRON_RENDERER_URL;
  if (devUrl) win.loadURL(devUrl);
  else win.loadURL(`${SCHEME}://${HOST}/index.html`);

  return win;
}

app.whenReady().then(() => {
  const root = rendererRoot();

  // Serve files under `root` for app://cartograph/<path>, with an index.html
  // fallback (harmless with hash routing, guards against odd asset paths).
  protocol.handle(SCHEME, async (request) => {
    const { pathname } = new URL(request.url);
    let rel = decodeURIComponent(pathname);
    if (!rel || rel === '/') rel = '/index.html';

    const filePath = path.normalize(path.join(root, rel));
    if (!filePath.startsWith(root)) {
      return new Response('Forbidden', { status: 403 });
    }
    try {
      return await net.fetch(pathToFileURL(filePath).toString());
    } catch {
      return await net.fetch(pathToFileURL(path.join(root, 'index.html')).toString());
    }
  });

  // Synchronous read for the preload bootstrap.
  ipcMain.on('config:get-sync', (event) => {
    event.returnValue = config.load();
  });
  ipcMain.handle('config:get', () => config.load());
  ipcMain.handle('config:set', (_event, url) => {
    config.save(url);
    // Reload so preload re-injects the new config and every service re-reads it.
    BrowserWindow.getAllWindows().forEach((w) => w.reload());
  });

  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
