import { neon } from '@neondatabase/serverless';

export type DatabaseQuery = <Row extends Record<string, unknown> = Record<string, unknown>>(
  strings: TemplateStringsArray,
  ...values: unknown[]
) => Promise<Row[]>;

export class DatabaseConfigurationError extends Error {
  constructor() {
    super('DATABASE_URL is not configured for the API.');
    this.name = 'DatabaseConfigurationError';
  }
}

let databaseClient: DatabaseQuery | undefined;

export function getDatabaseClient(): DatabaseQuery {
  const databaseURL = process.env.DATABASE_URL?.trim();

  if (!databaseURL) {
    throw new DatabaseConfigurationError();
  }

  databaseClient ??= neon(databaseURL) as DatabaseQuery;

  return databaseClient;
}

export function isDatabaseConfigured(): boolean {
  return Boolean(process.env.DATABASE_URL?.trim());
}

export function resetDatabaseClientForTests(): void {
  databaseClient = undefined;
}
