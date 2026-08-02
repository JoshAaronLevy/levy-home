#!/usr/bin/env node

import os from 'node:os';
import process from 'node:process';
import WebSocket from 'ws';

const DEFAULT_API_BASE_URL =
  process.env.RENDER_API_BASE_URL ||
  process.env.DEPLOYED_API_BASE_URL ||
  process.env.LEVY_HOME_API_BASE_URL ||
  'https://levy-home.onrender.com';
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_VIEWER_ID = 'stage11-render-verifier';
const DEFAULT_DISPLAY_NAME = 'Stage 11 verifier';

const options = readOptions(process.argv.slice(2));

if (options.help) {
  printHelp();
  process.exit(0);
}

const liveURL = liveURLForBaseURL(options.apiBaseURL);
const socketMessages = [];
const pendingWaiters = [];
let socket;

try {
  console.log(`Render API: ${redactedURL(options.apiBaseURL)}`);
  console.log(`Render WebSocket: ${redactedURL(liveURL)}`);

  await checkHTTP();
  await checkWebSocket();

  if (options.writeProof) {
    await runWriteProof();
  } else {
    console.log('Skipping deployed write proof. Pass --write-proof to create, update, and delete a temporary item.');
  }

  console.log('Render shopping-list readiness checks passed.');
} finally {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.close(1000, 'Stage 11 verifier complete.');
  }
}

async function checkHTTP() {
  const health = await fetchJSON('/health');

  if (health.ok !== true) {
    throw new Error('/health did not return ok=true.');
  }

  console.log(`/health ok service=${health.service ?? 'unknown'} uptimeSeconds=${health.uptimeSeconds ?? 'unknown'}`);

  const shoppingList = await fetchJSON('/api/shopping-list');

  if (
    shoppingList.ok !== true ||
    !Array.isArray(shoppingList.items) ||
    !Array.isArray(shoppingList.stores) ||
    !Array.isArray(shoppingList.categories)
  ) {
    throw new Error('/api/shopping-list did not return the expected shopping-list shape.');
  }

  console.log(
    `/api/shopping-list ok items=${shoppingList.items.length} stores=${shoppingList.stores.length} categories=${shoppingList.categories.length}`,
  );
}

async function checkWebSocket() {
  socket = new WebSocket(liveURL);

  await waitForSocketOpen(socket);
  sendJSON({
    type: 'subscribe',
    viewerId: options.viewerId,
    displayName: options.displayName,
    deviceName: `Render verifier on ${os.hostname()}`,
  });

  const hello = await waitForMessage((message) => message.type === 'hello', 'hello');
  console.log(`WebSocket hello ok connection=${hello.connectionId}`);

  const snapshotRequired = await waitForMessage(
    (message) => message.type === 'snapshot_required',
    'snapshot_required',
  );
  console.log(`WebSocket snapshot_required ok reason=${snapshotRequired.reason}`);

  const presenceChanged = await waitForMessage(
    (message) =>
      message.type === 'presence_changed' &&
      Array.isArray(message.viewers) &&
      message.viewers.some((viewer) => viewer.viewerId === canonicalViewerId(options.viewerId)),
    'presence_changed including verifier',
  );
  console.log(`WebSocket presence_changed ok viewers=${describeViewers(presenceChanged.viewers)}`);
}

async function runWriteProof() {
  const proofName = `Stage 11 Render proof ${new Date().toISOString()}`;
  let itemId;

  try {
    const createMutationId = mutationId('create');
    const createResponse = await fetchJSON('/api/shopping-list/items', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: proofName,
        quantity: 1,
        notes: 'Temporary deployed realtime proof.',
        mutationId: createMutationId,
      }),
    });

    itemId = createResponse.item?.id;

    if (!Number.isInteger(itemId)) {
      throw new Error('Create proof response did not include an integer item id.');
    }

    await waitForMessage(
      (message) => message.type === 'item_created' && message.mutationId === createMutationId,
      'item_created proof broadcast',
    );
    console.log(`Write proof create ok itemId=${itemId}`);

    const updateMutationId = mutationId('update');
    await fetchJSON(`/api/shopping-list/items/${itemId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        quantity: 2,
        mutationId: updateMutationId,
      }),
    });
    await waitForMessage(
      (message) => message.type === 'item_updated' && message.mutationId === updateMutationId,
      'item_updated proof broadcast',
    );
    console.log(`Write proof update ok itemId=${itemId}`);

    const deleteMutationId = mutationId('delete');
    await fetchJSON(`/api/shopping-list/items/${itemId}`, {
      method: 'DELETE',
      headers: { 'X-Levy-Home-Mutation-ID': deleteMutationId },
    });
    await waitForMessage(
      (message) => message.type === 'item_deleted' && message.mutationId === deleteMutationId,
      'item_deleted proof broadcast',
    );
    console.log(`Write proof delete ok itemId=${itemId}`);
  } catch (error) {
    if (itemId) {
      await tryCleanup(itemId);
    }

    throw error;
  }
}

async function tryCleanup(itemId) {
  try {
    await fetchJSON(`/api/shopping-list/items/${itemId}`, {
      method: 'DELETE',
      headers: { 'X-Levy-Home-Mutation-ID': mutationId('cleanup') },
    });
    console.warn(`Cleaned up proof item ${itemId} after failure.`);
  } catch (error) {
    console.warn(`Could not clean up proof item ${itemId}: ${error.message}`);
  }
}

async function fetchJSON(pathname, init) {
  const url = new URL(pathname, options.apiBaseURL);
  const response = await fetchWithTimeout(url, init);
  const text = await response.text();
  const body = parseResponseBody(text);

  if (!response.ok) {
    throw new Error(`${pathname} failed with HTTP ${response.status}: ${safeErrorBody(body)}`);
  }

  return body;
}

async function fetchWithTimeout(url, init = {}) {
  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), options.timeoutMS);

  try {
    return await fetch(url, {
      ...init,
      signal: abortController.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

function waitForSocketOpen(activeSocket) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for WebSocket open after ${options.timeoutMS} ms.`));
    }, options.timeoutMS);

    const onOpen = () => {
      cleanup();
      resolve();
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };

    function cleanup() {
      clearTimeout(timeout);
      activeSocket.off('open', onOpen);
      activeSocket.off('error', onError);
    }

    activeSocket.once('open', onOpen);
    activeSocket.once('error', onError);
    activeSocket.on('message', handleSocketMessage);
  });
}

function handleSocketMessage(data, isBinary) {
  if (isBinary) {
    return;
  }

  try {
    const message = JSON.parse(data.toString('utf8'));
    socketMessages.push(message);
    settleWaiters();
  } catch {
    // Ignore malformed diagnostics from non-Levy endpoints.
  }
}

function waitForMessage(predicate, label) {
  const existingMessage = socketMessages.find(predicate);

  if (existingMessage) {
    return Promise.resolve(existingMessage);
  }

  return new Promise((resolve, reject) => {
    const waiter = {
      predicate,
      label,
      resolve,
      reject,
      timeout: setTimeout(() => {
        removeWaiter(waiter);
        reject(new Error(`Timed out waiting for WebSocket message: ${label}.`));
      }, options.timeoutMS),
    };

    pendingWaiters.push(waiter);
    settleWaiters();
  });
}

function settleWaiters() {
  for (const waiter of [...pendingWaiters]) {
    const message = socketMessages.find(waiter.predicate);

    if (!message) {
      continue;
    }

    removeWaiter(waiter);
    waiter.resolve(message);
  }
}

function removeWaiter(waiter) {
  clearTimeout(waiter.timeout);
  const index = pendingWaiters.indexOf(waiter);

  if (index !== -1) {
    pendingWaiters.splice(index, 1);
  }
}

function sendJSON(value) {
  socket.send(JSON.stringify(value));
}

function readOptions(args) {
  const parsed = {
    apiBaseURL: DEFAULT_API_BASE_URL,
    viewerId: DEFAULT_VIEWER_ID,
    displayName: DEFAULT_DISPLAY_NAME,
    timeoutMS: DEFAULT_TIMEOUT_MS,
    writeProof: false,
    allowInsecure: false,
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

    if (arg === '--viewer-id') {
      parsed.viewerId = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--display-name') {
      parsed.displayName = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--timeout-ms') {
      const timeoutMS = Number(requireValue(args, ++index, arg));

      if (!Number.isFinite(timeoutMS) || timeoutMS < 1_000) {
        throw new Error('--timeout-ms must be at least 1000.');
      }

      parsed.timeoutMS = timeoutMS;
      continue;
    }

    if (arg === '--write-proof') {
      parsed.writeProof = true;
      continue;
    }

    if (arg === '--allow-insecure') {
      parsed.allowInsecure = true;
      continue;
    }

    throw new Error(`Unknown option: ${arg}`);
  }

  parsed.apiBaseURL = normalizeBaseURL(parsed.apiBaseURL, parsed.allowInsecure);
  parsed.viewerId = parsed.viewerId.trim();
  parsed.displayName = parsed.displayName.trim();

  if (!parsed.viewerId) {
    throw new Error('--viewer-id cannot be empty.');
  }

  if (!parsed.displayName) {
    throw new Error('--display-name cannot be empty.');
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

function normalizeBaseURL(value, allowInsecure) {
  const url = new URL(value);

  if (url.protocol !== 'https:' && !(allowInsecure && url.protocol === 'http:')) {
    throw new Error('--api-base-url must use https:// for deployed Render checks. Use --allow-insecure only for diagnostics.');
  }

  url.pathname = url.pathname.replace(/\/+$/, '');
  url.search = '';
  url.hash = '';

  return url;
}

function liveURLForBaseURL(baseURL) {
  const url = new URL(baseURL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';

  const basePath = url.pathname.replace(/^\/+|\/+$/g, '');
  url.pathname = `/${[basePath, 'api/shopping-list/live'].filter(Boolean).join('/')}`;
  url.search = '';
  url.hash = '';

  return url;
}

function describeViewers(viewers) {
  return viewers
    .map((viewer) => `${viewer.displayName ?? 'Unknown'}(${viewer.viewerId ?? 'unknown'})`)
    .join(', ');
}

// The API canonicalizes presence IDs before broadcasting them. Keep this
// verifier aligned with that public realtime contract, including custom IDs
// supplied with punctuation such as "stage-12-verifier".
function canonicalViewerId(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function mutationId(action) {
  return `stage11-render-${action}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function redactedURL(url) {
  const safeURL = new URL(url);
  safeURL.username = '';
  safeURL.password = '';
  return safeURL.toString();
}

function safeErrorBody(body) {
  if (!body || typeof body !== 'object') {
    return String(body);
  }

  return body.code ?? body.error ?? JSON.stringify(body);
}

function parseResponseBody(text) {
  if (!text) {
    return null;
  }

  try {
    return JSON.parse(text);
  } catch {
    return text.slice(0, 300);
  }
}

function printHelp() {
  console.log(`Usage:
  node scripts/verify-shopping-list-render-readiness.mjs [options]

Options:
  --api-base-url <url>   Deployed Render API URL. Default: ${DEFAULT_API_BASE_URL}
  --viewer-id <id>       WebSocket presence viewer id. Default: ${DEFAULT_VIEWER_ID}
  --display-name <name>  WebSocket presence display name. Default: ${DEFAULT_DISPLAY_NAME}
  --timeout-ms <ms>      Timeout for HTTP/WebSocket checks. Default: ${DEFAULT_TIMEOUT_MS}
  --write-proof          Create, update, and delete a temporary deployed shopping item.
  --allow-insecure       Allow http:// for diagnostics. Deployed checks should use https://.
  --help                 Show this help.

Examples:
  node scripts/verify-shopping-list-render-readiness.mjs
  node scripts/verify-shopping-list-render-readiness.mjs --api-base-url https://levy-home.onrender.com
  node scripts/verify-shopping-list-render-readiness.mjs --write-proof
`);
}
