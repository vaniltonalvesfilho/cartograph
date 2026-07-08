// Backend address persistence + URL derivation. Shared by main (fs load/save)
// and preload (deriveConfig only — a pure function, so it is safe there even
// though `app` is undefined outside the main process).
const { app } = require('electron');
const fs = require('fs');
const path = require('path');

const DEFAULT_URL = 'http://localhost:8080';

function configPath() {
  return path.join(app.getPath('userData'), 'config.json');
}

// Returns the persisted server URL, or the default when absent/unreadable.
function load() {
  try {
    const data = JSON.parse(fs.readFileSync(configPath(), 'utf8'));
    if (typeof data.serverUrl === 'string' && data.serverUrl) return data.serverUrl;
  } catch {
    // no config yet, or malformed — fall through to default
  }
  return DEFAULT_URL;
}

function save(serverUrl) {
  fs.writeFileSync(configPath(), JSON.stringify({ serverUrl }, null, 2));
}

// Turns a base URL (http://host:port) into the three endpoints the Angular app
// reads via window.cartograph.config.
function deriveConfig(serverUrl) {
  const base = (serverUrl || DEFAULT_URL).replace(/\/+$/, '');
  const ws = base.replace(/^http/i, 'ws');
  return {
    apiBase: `${base}/api`,
    graphqlHttp: `${base}/graphql`,
    socketUrl: `${ws}/socket`,
  };
}

module.exports = { load, save, deriveConfig, DEFAULT_URL };
