#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const DEFAULT_ENV_PATH = 'apps/api/.env';
const DEFAULT_OUTPUT_PATH = 'ha-system-catalog.json';
const DEFAULT_DAYS = 14;

async function main() {
  const options = readOptions(process.argv.slice(2));
  loadEnvFile(options.envPath);

  const baseURL = process.env.HOME_ASSISTANT_BASE_URL || process.env.HOME_ASSISTANT_LOCAL_URL;
  const token = process.env.HOME_ASSISTANT_TOKEN;

  if (!baseURL || !token) {
    throw new Error(
      `Missing Home Assistant config. Set HOME_ASSISTANT_BASE_URL or HOME_ASSISTANT_LOCAL_URL plus HOME_ASSISTANT_TOKEN in ${options.envPath}.`,
    );
  }

  const client = createHomeAssistantClient(baseURL, token);
  const now = new Date();
  const windowStart = new Date(now.getTime() - options.days * 24 * 60 * 60 * 1000);

  const [config, states, events, services, components, logbook, websocket] = await Promise.all([
    client.restJSON('/api/config'),
    client.restJSON('/api/states'),
    client.restJSON('/api/events'),
    client.restJSON('/api/services'),
    client.restJSON('/api/components'),
    client.restJSON(
      `/api/logbook/${encodeURIComponent(windowStart.toISOString())}?end_time=${encodeURIComponent(now.toISOString())}`,
    ),
    client.websocketCommands([
      { label: 'entityRegistry', type: 'config/entity_registry/list' },
      { label: 'entityRegistryForDisplay', type: 'config/entity_registry/list_for_display' },
      { label: 'deviceRegistry', type: 'config/device_registry/list' },
      { label: 'areaRegistry', type: 'config/area_registry/list' },
      { label: 'floorRegistry', type: 'config/floor_registry/list' },
      { label: 'labelRegistry', type: 'config/label_registry/list' },
      { label: 'automationTraces', type: 'trace/list', payload: { domain: 'automation' } },
      { label: 'scriptTraces', type: 'trace/list', payload: { domain: 'script' } },
    ]),
  ]);

  const raw = {
    config,
    states,
    events,
    services,
    components,
    logbook,
    websocket,
  };

  const catalog = buildCatalog(raw, {
    generatedAt: now.toISOString(),
    envPath: options.envPath,
    windowStart: windowStart.toISOString(),
    windowEnd: now.toISOString(),
    includeSensitive: options.includeSensitive,
  });

  if (options.includeSensitive) {
    catalog.raw = raw;
  }

  fs.writeFileSync(options.outputPath, `${JSON.stringify(catalog, null, 2)}\n`);

  console.log(`Wrote ${options.outputPath}`);
  console.log(
    JSON.stringify(
      {
        entities: catalog.counts.entities,
        registryEntities: catalog.counts.entityRegistryEntries,
        devices: catalog.counts.devices,
        areas: catalog.counts.areas,
        automations: catalog.counts.automations,
        automationTraceRuns: catalog.counts.automationTraceRuns,
      },
      null,
      2,
    ),
  );
}

function readOptions(args) {
  const options = {
    envPath: DEFAULT_ENV_PATH,
    outputPath: DEFAULT_OUTPUT_PATH,
    days: DEFAULT_DAYS,
    includeSensitive: false,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === '--env') {
      options.envPath = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--output') {
      options.outputPath = requireValue(args, ++index, arg);
      continue;
    }

    if (arg === '--days') {
      const days = Number(requireValue(args, ++index, arg));
      if (!Number.isFinite(days) || days <= 0) {
        throw new Error('--days must be a positive number.');
      }
      options.days = days;
      continue;
    }

    if (arg === '--include-sensitive') {
      options.includeSensitive = true;
      continue;
    }

    if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    }

    throw new Error(`Unknown option: ${arg}`);
  }

  return options;
}

function requireValue(args, index, option) {
  const value = args[index];

  if (!value || value.startsWith('--')) {
    throw new Error(`${option} requires a value.`);
  }

  return value;
}

function printHelp() {
  console.log(`Usage: node scripts/export-home-assistant-catalog.js [options]

Options:
  --env <path>       Env file to read. Default: ${DEFAULT_ENV_PATH}
  --output <path>    JSON file to write. Default: ${DEFAULT_OUTPUT_PATH}
  --days <number>    Logbook/history lookback window. Default: ${DEFAULT_DAYS}
  --include-sensitive
                    Include raw Home Assistant API payloads. Default output redacts
                    location/network/SIM-like current values and omits raw payloads.
`);
}

function loadEnvFile(envPath) {
  if (!fs.existsSync(envPath)) {
    return;
  }

  const contents = fs.readFileSync(envPath, 'utf8');

  for (const line of contents.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);

    if (!match) {
      continue;
    }

    const [, key, rawValue] = match;
    let value = rawValue.trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (process.env[key] == null) {
      process.env[key] = value.replace(/\\n/g, '\n');
    }
  }
}

function createHomeAssistantClient(baseURL, token) {
  const normalizedBaseURL = baseURL.endsWith('/') ? baseURL : `${baseURL}/`;
  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  return {
    restJSON: async (endpoint) => {
      const response = await fetch(new URL(endpoint, normalizedBaseURL), { headers });

      if (!response.ok) {
        throw new Error(`${endpoint} returned ${response.status} ${response.statusText}`);
      }

      return response.json();
    },

    websocketCommands: (commands) =>
      new Promise((resolve) => {
        const output = {};
        const pending = new Map();
        let nextId = 1;
        let settled = false;

        const websocketURL = process.env.HOME_ASSISTANT_WEBSOCKET_URL || deriveWebSocketURL(baseURL);
        const websocket = new WebSocket(websocketURL);
        const timer = setTimeout(() => finish(), 20_000);

        function finish() {
          if (settled) {
            return;
          }

          settled = true;
          clearTimeout(timer);

          try {
            websocket.close();
          } catch {
            // Closing is best-effort; the catalog can still include partial results.
          }

          resolve(output);
        }

        websocket.addEventListener('message', (event) => {
          let message;

          try {
            message = JSON.parse(event.data);
          } catch {
            return;
          }

          if (message.type === 'auth_required') {
            websocket.send(JSON.stringify({ type: 'auth', access_token: token }));
            return;
          }

          if (message.type === 'auth_invalid') {
            output.auth = { ok: false, error: message };
            finish();
            return;
          }

          if (message.type === 'auth_ok') {
            for (const command of commands) {
              const id = nextId;
              nextId += 1;
              pending.set(id, command.label);
              websocket.send(JSON.stringify({ id, type: command.type, ...(command.payload || {}) }));
            }

            if (pending.size === 0) {
              finish();
            }

            return;
          }

          if (message.type === 'result' && pending.has(message.id)) {
            const label = pending.get(message.id);
            pending.delete(message.id);
            output[label] = message.success
              ? { ok: true, result: message.result }
              : { ok: false, error: message.error || null };

            if (pending.size === 0) {
              finish();
            }
          }
        });

        websocket.addEventListener('error', () => {
          output.websocket = { ok: false, error: 'WebSocket request failed.' };
          finish();
        });
      }),
  };
}

function deriveWebSocketURL(baseURL) {
  const url = new URL('/api/websocket', baseURL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  return url.toString();
}

function buildCatalog(raw, options) {
  const states = asArray(raw.states);
  const stateByEntityId = new Map(states.map((state) => [state.entity_id, state]));
  const entityRegistry = readWebSocketArray(raw.websocket.entityRegistry);
  const entityDisplayRegistry = readWebSocketDisplayRegistry(raw.websocket.entityRegistryForDisplay);
  const deviceRegistry = readWebSocketArray(raw.websocket.deviceRegistry);
  const areaRegistry = readWebSocketArray(raw.websocket.areaRegistry);
  const floorRegistry = readWebSocketArray(raw.websocket.floorRegistry);
  const labelRegistry = readWebSocketArray(raw.websocket.labelRegistry);
  const automationTraces = readWebSocketArray(raw.websocket.automationTraces);
  const scriptTraces = readWebSocketArray(raw.websocket.scriptTraces);

  const entityIds = new Set([
    ...states.map((state) => state.entity_id),
    ...entityRegistry.map((entity) => entity.entity_id),
    ...entityDisplayRegistry.keys(),
  ]);

  const labelsById = new Map(labelRegistry.map((label) => [label.label_id || label.id, label]));
  const floorsById = new Map(floorRegistry.map((floor) => [floor.floor_id || floor.id, floor]));
  const areasById = new Map(areaRegistry.map((area) => [area.area_id || area.id, area]));
  const devicesById = new Map(deviceRegistry.map((device) => [device.id, device]));
  const registryByEntityId = new Map(entityRegistry.map((entity) => [entity.entity_id, entity]));

  const entities = [...entityIds]
    .filter(Boolean)
    .sort()
    .map((entityId) => {
      const registryEntry = registryByEntityId.get(entityId);
      const displayEntry = entityDisplayRegistry.get(entityId);
      const state = stateByEntityId.get(entityId);
      const areaId = registryEntry?.area_id || displayEntry?.areaId || null;
      const deviceId = registryEntry?.device_id || displayEntry?.deviceId || null;
      const device = deviceId ? devicesById.get(deviceId) : null;
      const resolvedAreaId = areaId || device?.area_id || null;
      const area = resolvedAreaId ? areasById.get(resolvedAreaId) : null;
      const labelIds = uniqueStrings([
        ...asArray(registryEntry?.labels),
        ...asArray(displayEntry?.labelIds),
      ]);

      return removeUndefined({
        entityId,
        domain: domainOf(entityId),
        platform: registryEntry?.platform || displayEntry?.platform || null,
        name:
          registryEntry?.name ||
          registryEntry?.original_name ||
          displayEntry?.name ||
          state?.attributes?.friendly_name ||
          null,
        originalName: registryEntry?.original_name || null,
        areaId: resolvedAreaId,
        areaName: area?.name || null,
        floorId: area?.floor_id || null,
        floorName: area?.floor_id ? floorsById.get(area.floor_id)?.name || null : null,
        deviceId,
        deviceName: device?.name_by_user || device?.name || null,
        labelIds,
        labels: labelIds.map((id) => labelsById.get(id)?.name || id),
        entityCategory: registryEntry?.entity_category || displayEntry?.entityCategory || null,
        disabledBy: registryEntry?.disabled_by || null,
        hiddenBy: registryEntry?.hidden_by || null,
        state: state ? sanitizeState(state, options.includeSensitive) : null,
      });
    });

  const entityIdsByDeviceId = groupIds(entities, (entity) => entity.deviceId);
  const entityIdsByAreaId = groupIds(entities, (entity) => entity.areaId);
  const deviceIdsByAreaId = groupIds(
    deviceRegistry.map((device) => ({ id: device.id, areaId: device.area_id || null })),
    (device) => device.areaId,
    (device) => device.id,
  );

  const devices = deviceRegistry
    .map((device) => {
      const area = device.area_id ? areasById.get(device.area_id) : null;

      return removeUndefined({
        id: device.id,
        name: device.name_by_user || device.name || null,
        manufacturer: device.manufacturer || null,
        model: device.model || null,
        areaId: device.area_id || null,
        areaName: area?.name || null,
        floorId: area?.floor_id || null,
        floorName: area?.floor_id ? floorsById.get(area.floor_id)?.name || null : null,
        labels: asArray(device.labels).map((id) => labelsById.get(id)?.name || id),
        disabledBy: device.disabled_by || null,
        entryType: device.entry_type || null,
        entityIds: entityIdsByDeviceId.get(device.id) || [],
      });
    })
    .sort(compareByNameThenId);

  const areas = areaRegistry
    .map((area) => {
      const areaId = area.area_id || area.id;

      return removeUndefined({
        id: areaId,
        name: area.name || null,
        floorId: area.floor_id || null,
        floorName: area.floor_id ? floorsById.get(area.floor_id)?.name || null : null,
        labels: asArray(area.labels).map((id) => labelsById.get(id)?.name || id),
        deviceIds: deviceIdsByAreaId.get(areaId) || [],
        entityIds: entityIdsByAreaId.get(areaId) || [],
      });
    })
    .sort(compareByNameThenId);

  const areaIdsByFloorId = groupIds(areas, (area) => area.floorId, (area) => area.id);
  const floors = floorRegistry
    .map((floor) => {
      const floorId = floor.floor_id || floor.id;

      return removeUndefined({
        id: floorId,
        name: floor.name || null,
        areaIds: areaIdsByFloorId.get(floorId) || [],
      });
    })
    .sort(compareByNameThenId);

  const tracesByAutomationId = groupObjects(automationTraces, (trace) => trace.item_id);
  const automations = entities
    .filter((entity) => entity.domain === 'automation')
    .map((entity) => {
      const state = stateByEntityId.get(entity.entityId);
      const automationId = state?.attributes?.id || entity.entityId.replace(/^automation\./, '');
      const traces = asArray(tracesByAutomationId.get(automationId)).map(sanitizeTrace);

      return removeUndefined({
        entityId: entity.entityId,
        id: automationId,
        name: entity.name,
        state: state?.state || null,
        lastTriggeredAt: state?.attributes?.last_triggered || null,
        mode: state?.attributes?.mode || null,
        current: state?.attributes?.current ?? null,
        areaId: entity.areaId,
        deviceId: entity.deviceId,
        traceRuns: traces,
      });
    })
    .sort(compareByNameThenId);

  const services = asArray(raw.services).map((serviceDomain) => ({
    domain: serviceDomain.domain,
    serviceCount: Array.isArray(serviceDomain.services)
      ? serviceDomain.services.length
      : Object.keys(serviceDomain.services || {}).length,
    services: Array.isArray(serviceDomain.services)
      ? [...serviceDomain.services].sort()
      : Object.keys(serviceDomain.services || {}).sort(),
  }));

  return {
    generatedAt: options.generatedAt,
    source: {
      envPath: options.envPath,
      restEndpoints: ['/api/config', '/api/states', '/api/events', '/api/services', '/api/components', '/api/logbook/<start>'],
      websocketCommands: [
        'config/entity_registry/list',
        'config/entity_registry/list_for_display',
        'config/device_registry/list',
        'config/area_registry/list',
        'config/floor_registry/list',
        'config/label_registry/list',
        'trace/list domain=automation',
        'trace/list domain=script',
      ],
    },
    privacy: options.includeSensitive
      ? 'Raw Home Assistant payloads are included because --include-sensitive was passed.'
      : 'Default output omits raw payloads and redacts location/network/SIM-like current values.',
    window: {
      start: options.windowStart,
      end: options.windowEnd,
    },
    counts: {
      entities: entities.length,
      currentStateEntities: states.length,
      entityRegistryEntries: entityRegistry.length,
      devices: devices.length,
      areas: areas.length,
      floors: floors.length,
      labels: labelRegistry.length,
      automations: automations.length,
      automationTraceRuns: automationTraces.length,
      scriptTraceRuns: scriptTraces.length,
      registeredEventTypes: asArray(raw.events).length,
      serviceDomains: services.length,
      components: asArray(raw.components).length,
      logbookEntries: asArray(raw.logbook).length,
    },
    homeAssistant: sanitizeConfig(raw.config),
    floors,
    areas,
    devices,
    labels: labelRegistry
      .map((label) => ({ id: label.label_id || label.id, name: label.name || null }))
      .sort(compareByNameThenId),
    entities,
    automations,
    traces: {
      automation: automationTraces.map(sanitizeTrace),
      script: scriptTraces.map(sanitizeTrace),
    },
    events: asArray(raw.events).sort((a, b) => String(a.event).localeCompare(String(b.event))),
    services: services.sort((a, b) => a.domain.localeCompare(b.domain)),
    components: asArray(raw.components).sort(),
    logbook: asArray(raw.logbook).map((entry) => ({
      when: entry.when || null,
      domain: entry.domain || null,
      entityId: entry.entity_id || null,
      name: entry.name || null,
      message: entry.message || null,
    })),
    summaries: {
      entitiesByDomain: countBy(entities, (entity) => entity.domain),
      entitiesByPlatform: countBy(entities, (entity) => entity.platform || 'unknown'),
      entitiesByArea: countBy(entities, (entity) => entity.areaName || entity.areaId || 'unassigned'),
      devicesByArea: countBy(devices, (device) => device.areaName || device.areaId || 'unassigned'),
      logbookByDomain: countBy(asArray(raw.logbook), (entry) => entry.domain || 'unknown'),
    },
  };
}

function readWebSocketArray(response) {
  return response?.ok && Array.isArray(response.result) ? response.result : [];
}

function readWebSocketDisplayRegistry(response) {
  const result = new Map();

  if (!response?.ok || !response.result || !Array.isArray(response.result.entities)) {
    return result;
  }

  const categories = response.result.entity_categories || {};

  for (const entry of response.result.entities) {
    if (!entry.ei) {
      continue;
    }

    result.set(entry.ei, {
      platform: entry.pl || null,
      areaId: entry.ai || null,
      deviceId: entry.di || null,
      name: entry.en || null,
      labelIds: asArray(entry.lb),
      entityCategory: entry.ec != null ? categories[entry.ec] || null : null,
    });
  }

  return result;
}

function sanitizeState(state, includeSensitive) {
  const attributes = state.attributes || {};

  return {
    value: previewState(state.state, state.entity_id, attributes, includeSensitive),
    lastChangedAt: state.last_changed || null,
    lastUpdatedAt: state.last_updated || null,
    attributes: includeSensitive ? attributes : safeAttributes(attributes),
    attributeKeys: Object.keys(attributes).sort(),
  };
}

function safeAttributes(attributes) {
  const allowed = [
    'friendly_name',
    'device_class',
    'state_class',
    'unit_of_measurement',
    'icon',
    'source_type',
    'battery_level',
    'mode',
    'current',
    'last_triggered',
    'id',
  ];
  const result = {};

  for (const key of allowed) {
    if (attributes[key] != null && !isSensitiveKey(key)) {
      result[key] = attributes[key];
    }
  }

  return result;
}

function previewState(value, entityId, attributes, includeSensitive) {
  if (value == null) {
    return null;
  }

  if (!includeSensitive && isSensitiveEntity(entityId, attributes)) {
    return '[redacted]';
  }

  const text = String(value);
  return text.length > 160 ? `${text.slice(0, 157)}...` : text;
}

function sanitizeConfig(config) {
  return {
    components: asArray(config?.components).sort(),
    country: config?.country || null,
    currency: config?.currency || null,
    language: config?.language || null,
    locationName: config?.location_name || null,
    state: config?.state || null,
    timeZone: config?.time_zone || null,
    unitSystem: config?.unit_system || null,
    version: config?.version || null,
  };
}

function sanitizeTrace(trace) {
  return {
    domain: trace.domain || null,
    itemId: trace.item_id || null,
    runId: trace.run_id || null,
    state: trace.state || null,
    scriptExecution: trace.script_execution || null,
    trigger: trace.trigger || null,
    lastStep: trace.last_step || null,
    startedAt: trace.timestamp?.start || null,
    finishedAt: trace.timestamp?.finish || null,
  };
}

function isSensitiveEntity(entityId, attributes = {}) {
  const haystack = `${entityId} ${attributes.friendly_name || ''} ${attributes.device_class || ''}`.toLowerCase();
  return /(address|geocoded|location|latitude|longitude|gps|ssid|bssid|sim|wifi|wi-fi|wi_fi|ip_address|mac_address)/.test(
    haystack,
  );
}

function isSensitiveKey(key) {
  return /(address|geocoded|location|latitude|longitude|gps|ssid|bssid|sim|wifi|wi-fi|wi_fi|ip_address|mac_address)/i.test(
    key,
  );
}

function domainOf(entityId) {
  return String(entityId || '').split('.')[0] || 'unknown';
}

function countBy(items, getKey) {
  const counts = new Map();

  for (const item of items) {
    const key = getKey(item) || 'unknown';
    counts.set(key, (counts.get(key) || 0) + 1);
  }

  return Object.fromEntries([...counts.entries()].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0]))));
}

function groupIds(items, getGroupId, getItemId = (item) => item.entityId || item.id) {
  const groups = new Map();

  for (const item of items) {
    const groupId = getGroupId(item);

    if (!groupId) {
      continue;
    }

    const ids = groups.get(groupId) || [];
    const itemId = getItemId(item);

    if (itemId) {
      ids.push(itemId);
    }

    groups.set(groupId, ids);
  }

  for (const [groupId, ids] of groups.entries()) {
    groups.set(groupId, uniqueStrings(ids).sort());
  }

  return groups;
}

function groupObjects(items, getGroupId) {
  const groups = new Map();

  for (const item of items) {
    const groupId = getGroupId(item);

    if (!groupId) {
      continue;
    }

    const group = groups.get(groupId) || [];
    group.push(item);
    groups.set(groupId, group);
  }

  return groups;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === 'string' && value.trim()).map((value) => value.trim()))];
}

function removeUndefined(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entryValue]) => entryValue !== undefined));
}

function compareByNameThenId(a, b) {
  return String(a.name || a.id || a.entityId).localeCompare(String(b.name || b.id || b.entityId));
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
