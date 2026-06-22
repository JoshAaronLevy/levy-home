#!/usr/bin/env node

import os from 'node:os';
import process from 'node:process';
import WebSocket from 'ws';

const DEFAULT_API_BASE_URL =
  process.env.LEVY_HOME_API_BASE_URL ||
  process.env.API_BASE_URL ||
  'http://localhost:4000';
const DEFAULT_VIEWER_ID = process.env.VIEWER_ID || 'manual-client';
const DEFAULT_PING_INTERVAL_MS = 25_000;

const options = readOptions(process.argv.slice(2));

if (options.help) {
  printHelp();
  process.exit(0);
}

const liveURL = options.webSocketURL ?? liveURLForBaseURL(options.apiBaseURL);
const displayName = options.displayName ?? displayNameForViewerId(options.viewerId);
const deviceName = options.deviceName ?? `Terminal on ${os.hostname()}`;
const pingIntervalMS = options.pingIntervalMS ?? DEFAULT_PING_INTERVAL_MS;

console.log(`Connecting to ${redactedURL(liveURL)}`);
console.log(`Subscribing as ${displayName} (${options.viewerId})`);

const socket = new WebSocket(liveURL);
let pingTimer;

socket.on('open', () => {
  sendJSON({
    type: 'subscribe',
    viewerId: options.viewerId,
    displayName,
    deviceName,
  });

  pingTimer = setInterval(() => {
    sendJSON({
      type: 'presence_ping',
      viewerId: options.viewerId,
    });
  }, pingIntervalMS);
  pingTimer.unref();
});

socket.on('message', (data, isBinary) => {
  if (isBinary) {
    console.log(`${timestamp()} binary message ${data.length} byte(s)`);
    return;
  }

  const text = data.toString('utf8');

  if (options.raw) {
    console.log(text);
    return;
  }

  try {
    console.log(`${timestamp()} ${describeMessage(JSON.parse(text))}`);
  } catch {
    console.log(`${timestamp()} ${text}`);
  }
});

socket.on('close', (code, reason) => {
  clearInterval(pingTimer);
  const detail = reason.length > 0 ? ` ${reason.toString('utf8')}` : '';
  console.log(`Disconnected: ${code}${detail}`);
});

socket.on('error', (error) => {
  console.error(`WebSocket error: ${error.message}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.once(signal, () => {
    clearInterval(pingTimer);
    socket.close(1000, 'Manual client exiting.');
  });
}

function sendJSON(value) {
  if (socket.readyState !== WebSocket.OPEN) {
    return;
  }

  socket.send(JSON.stringify(value));
}

function readOptions(args) {
  const parsed = {
    apiBaseURL: DEFAULT_API_BASE_URL,
    viewerId: DEFAULT_VIEWER_ID,
    raw: false,
    help: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
      continue;
    }

    if (arg === '--api-base-url') {
      parsed.apiBaseURL = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--ws-url') {
      parsed.webSocketURL = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--viewer-id') {
      parsed.viewerId = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--display-name') {
      parsed.displayName = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--device-name') {
      parsed.deviceName = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--ping-interval-ms') {
      const value = Number(requireValue(args, ++index, arg));

      if (!Number.isFinite(value) || value < 1_000) {
        throw new Error('--ping-interval-ms must be at least 1000.');
      }

      parsed.pingIntervalMS = value;
      continue;
    }

    if (arg === '--raw') {
      parsed.raw = true;
      continue;
    }

    throw new Error(`Unknown option: ${arg}`);
  }

  parsed.apiBaseURL = normalizeBaseURL(parsed.apiBaseURL);
  parsed.webSocketURL = parsed.webSocketURL ? normalizeWebSocketURL(parsed.webSocketURL) : undefined;
  parsed.viewerId = parsed.viewerId.trim();

  if (!parsed.viewerId) {
    throw new Error('--viewer-id cannot be empty.');
  }

  return parsed;
}

function requireValue(args, index, optionName) {
  const value = args[index];

  if (!value || value.startsWith('--')) {
    throw new Error(`${optionName} requires a value.`);
  }

  return value;
}

function normalizeBaseURL(value) {
  const url = new URL(value);

  if (url.protocol !== 'http:' && url.protocol !== 'https:') {
    throw new Error('--api-base-url must start with http:// or https://.');
  }

  url.pathname = url.pathname.replace(/\/+$/, '');
  url.search = '';
  url.hash = '';

  return url;
}

function normalizeWebSocketURL(value) {
  const url = new URL(value);

  if (url.protocol !== 'ws:' && url.protocol !== 'wss:') {
    throw new Error('--ws-url must start with ws:// or wss://.');
  }

  return url;
}

function liveURLForBaseURL(baseURL) {
  const url = new URL(baseURL);

  if (url.protocol === 'http:') {
    url.protocol = 'ws:';
  } else if (url.protocol === 'https:') {
    url.protocol = 'wss:';
  }

  const basePath = url.pathname.replace(/^\/+|\/+$/g, '');
  url.pathname = `/${[basePath, 'api/shopping-list/live'].filter(Boolean).join('/')}`;
  url.search = '';
  url.hash = '';

  return url;
}

function displayNameForViewerId(viewerId) {
  const normalized = viewerId.trim().toLowerCase();

  if (normalized === 'josh') {
    return 'Josh';
  }

  if (normalized === 'mallory') {
    return 'Mallory';
  }

  return viewerId
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1).toLowerCase())
    .join(' ') || 'Manual Client';
}

function describeMessage(message) {
  if (!message || typeof message !== 'object') {
    return JSON.stringify(message);
  }

  switch (message.type) {
    case 'hello':
      return `hello connection=${message.connectionId}`;
    case 'snapshot_required':
      return `snapshot_required reason=${message.reason}`;
    case 'presence_changed':
      return `presence_changed viewers=${describeViewers(message.viewers)}`;
    case 'item_created':
      return `item_created ${describeItem(message.item)} mutation=${message.mutationId}`;
    case 'item_updated':
      return `item_updated ${describeItem(message.item)} mutation=${message.mutationId}`;
    case 'item_deleted':
      return `item_deleted itemId=${message.itemId} mutation=${message.mutationId}`;
    case 'stores_changed':
      return `stores_changed count=${Array.isArray(message.stores) ? message.stores.length : 0}`;
    case 'categories_changed':
      return `categories_changed count=${Array.isArray(message.categories) ? message.categories.length : 0}`;
    default:
      return JSON.stringify(message);
  }
}

function describeViewers(viewers) {
  if (!Array.isArray(viewers) || viewers.length === 0) {
    return 'none';
  }

  return viewers
    .map((viewer) => {
      const display = viewer.displayName || viewer.viewerId || 'unknown';
      return viewer.viewerId ? `${display}(${viewer.viewerId})` : display;
    })
    .join(', ');
}

function describeItem(item) {
  if (!item || typeof item !== 'object') {
    return 'item=<missing>';
  }

  const name = typeof item.name === 'string' ? JSON.stringify(item.name) : '<unnamed>';
  return `#${item.id} ${name} qty=${item.quantity} purchased=${item.purchased}`;
}

function timestamp() {
  return new Date().toISOString();
}

function redactedURL(url) {
  const safeURL = new URL(url);
  safeURL.username = '';
  safeURL.password = '';
  return safeURL.toString();
}

function printHelp() {
  console.log(`Usage:
  node scripts/shopping-list-live-client.mjs [options]

Options:
  --api-base-url <url>      API base URL. Default: ${DEFAULT_API_BASE_URL}
  --ws-url <url>            Exact WebSocket URL, overriding --api-base-url.
  --viewer-id <id>          Presence viewer id. Default: ${DEFAULT_VIEWER_ID}
  --display-name <name>     Presence display name. Defaults from viewer id.
  --device-name <name>      Presence device name. Default: Terminal on this Mac.
  --ping-interval-ms <ms>   Presence ping interval. Default: ${DEFAULT_PING_INTERVAL_MS}
  --raw                     Print raw JSON messages.
  --help                    Show this help.

Examples:
  node scripts/shopping-list-live-client.mjs --viewer-id mallory --display-name Mallory
  API_BASE_URL=http://localhost:4000 node scripts/shopping-list-live-client.mjs --viewer-id josh
`);
}
