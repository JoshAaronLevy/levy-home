import { neon, neonConfig, Pool } from '@neondatabase/serverless';
import ws from 'ws';

export type DatabaseQuery = <Row extends Record<string, unknown> = Record<string, unknown>>(
  strings: TemplateStringsArray,
  ...values: unknown[]
) => Promise<Row[]>;

export type DatabaseTransactionRunner = <Result>(
  operation: (database: DatabaseQuery) => Promise<Result>,
) => Promise<Result>;

export type DatabaseSQLClient = {
  query: (
    text: string,
    values?: unknown[],
  ) => Promise<{ rows: unknown[] }>;
  release: () => void;
};

export class DatabaseConfigurationError extends Error {
  constructor() {
    super('DATABASE_URL is not configured for the API.');
    this.name = 'DatabaseConfigurationError';
  }
}

let databaseClient: DatabaseQuery | undefined;
let transactionPool: Pool | undefined;
let databaseTransactionRunner: DatabaseTransactionRunner | undefined;

export function getDatabaseClient(): DatabaseQuery {
  const databaseURL = requireDatabaseURL();

  databaseClient ??= neon(databaseURL) as DatabaseQuery;

  return databaseClient;
}

export function getDatabaseTransactionRunner(): DatabaseTransactionRunner {
  if (databaseTransactionRunner) {
    return databaseTransactionRunner;
  }

  const databaseURL = requireDatabaseURL();
  neonConfig.webSocketConstructor = ws;
  transactionPool ??= new Pool({ connectionString: databaseURL });
  databaseTransactionRunner = createDatabaseTransactionRunner(async () => {
    const client = await transactionPool!.connect();
    return client as unknown as DatabaseSQLClient;
  });

  return databaseTransactionRunner;
}

export function createDatabaseTransactionRunner(
  connect: () => Promise<DatabaseSQLClient>,
): DatabaseTransactionRunner {
  return async <Result>(operation: (database: DatabaseQuery) => Promise<Result>): Promise<Result> => {
    const client = await connect();

    try {
      await client.query('BEGIN');
      const result = await operation(createDatabaseQuery(client));
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  };
}

export function createDatabaseQuery(client: Pick<DatabaseSQLClient, 'query'>): DatabaseQuery {
  return async <Row extends Record<string, unknown> = Record<string, unknown>>(
    strings: TemplateStringsArray,
    ...values: unknown[]
  ): Promise<Row[]> => {
    const text = strings.reduce(
      (query, part, index) => query + part + (index < values.length ? `$${index + 1}` : ''),
      '',
    );
    const result = await client.query(text, values);
    return result.rows as Row[];
  };
}

export function isDatabaseConfigured(): boolean {
  return Boolean(process.env.DATABASE_URL?.trim());
}

export function resetDatabaseClientForTests(): void {
  databaseClient = undefined;
  databaseTransactionRunner = undefined;
}

function requireDatabaseURL(): string {
  const databaseURL = process.env.DATABASE_URL?.trim();

  if (!databaseURL) {
    throw new DatabaseConfigurationError();
  }

  return databaseURL;
}
