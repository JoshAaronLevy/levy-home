export type Logger = {
  debug: (message: string, details?: Record<string, unknown>) => void;
  error: (message: string, details?: Record<string, unknown>) => void;
  info: (message: string, details?: Record<string, unknown>) => void;
  warn: (message: string, details?: Record<string, unknown>) => void;
};

const sensitiveKeyPattern = /(authorization|client_secret|private_key|secret|token)/i;
const bearerTokenPattern = /Bearer\s+[A-Za-z0-9._~+/=-]+/gi;
const basicAuthPattern = /Basic\s+[A-Za-z0-9._~+/=-]+/gi;

export const logger: Logger = {
  debug(message, details) {
    console.debug(formatLogMessage(message, details));
  },
  error(message, details) {
    console.error(formatLogMessage(message, details));
  },
  info(message, details) {
    console.info(formatLogMessage(message, details));
  },
  warn(message, details) {
    console.warn(formatLogMessage(message, details));
  },
};

export function safeErrorMessage(error: unknown): string {
  return redactLogValue(error instanceof Error ? error.message : String(error));
}

export function redactLogValue(value: unknown): string {
  if (value instanceof Error) {
    return safeErrorMessage(value);
  }

  if (typeof value === 'string') {
    return redactString(value);
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }

  if (value === null || value === undefined) {
    return String(value);
  }

  return redactString(JSON.stringify(redactStructuredValue(value)));
}

function formatLogMessage(message: string, details?: Record<string, unknown>): string {
  const safeMessage = redactString(message);

  if (!details) {
    return safeMessage;
  }

  const detailText = Object.entries(redactStructuredValue(details) as Record<string, unknown>)
    .filter(([, value]) => value !== undefined)
    .map(([key, value]) => `${key}=${redactLogValue(value)}`)
    .join(' ');

  return detailText ? `${safeMessage} ${detailText}` : safeMessage;
}

function redactStructuredValue(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(redactStructuredValue);
  }

  if (!value || typeof value !== 'object') {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, entryValue]) => [
      key,
      sensitiveKeyPattern.test(key) ? '[redacted]' : redactStructuredValue(entryValue),
    ]),
  );
}

function redactString(value: string): string {
  return value
    .replace(bearerTokenPattern, 'Bearer [redacted]')
    .replace(basicAuthPattern, 'Basic [redacted]');
}
