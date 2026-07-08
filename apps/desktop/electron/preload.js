// Runs before the Angular bundle. Injects the backend config (read synchronously
// from the main process) and exposes get/set helpers for the server-settings
// screen. contextIsolation is on, so the renderer only sees `window.cartograph`.
const { contextBridge, ipcRenderer } = require('electron');
const { deriveConfig } = require('./config');

const serverUrl = ipcRenderer.sendSync('config:get-sync');

contextBridge.exposeInMainWorld('cartograph', {
  config: deriveConfig(serverUrl),
  getServerUrl: () => ipcRenderer.invoke('config:get'),
  setServerUrl: (url) => ipcRenderer.invoke('config:set', url),
});
