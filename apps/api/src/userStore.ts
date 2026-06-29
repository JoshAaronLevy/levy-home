import type { LevyHomeUser } from './contracts.js';
import { getDatabaseClient, type DatabaseQuery } from './dbClient.js';

export type UserStore = {
  fetchUsers: () => Promise<LevyHomeUser[]>;
};

type UserRow = Record<string, unknown> & {
  id: unknown;
  firstName: unknown;
  lastName: unknown;
  email: unknown;
  mobileDevice: unknown;
  lastLogin: unknown;
};

export function createPostgresUserStore(database?: DatabaseQuery): UserStore {
  const query = () => database ?? getDatabaseClient();

  return {
    async fetchUsers() {
      return fetchUsersData(query());
    },
  };
}

export async function fetchUsersData(database: DatabaseQuery): Promise<LevyHomeUser[]> {
  const rows = await database<UserRow>`
    SELECT
      id,
      first_name AS "firstName",
      last_name AS "lastName",
      email,
      mobile_device AS "mobileDevice",
      last_login AS "lastLogin"
    FROM users
    ORDER BY id ASC
  `;

  return rows.map(userFromRow);
}

function userFromRow(row: UserRow): LevyHomeUser {
  const mobileDevice = optionalString(row.mobileDevice);
  const lastLogin = optionalISOString(row.lastLogin);

  return {
    id: requiredInteger(row.id, 'users.id'),
    firstName: requiredString(row.firstName, 'users.first_name'),
    lastName: requiredString(row.lastName, 'users.last_name'),
    email: requiredString(row.email, 'users.email'),
    ...(mobileDevice ? { mobileDevice } : {}),
    ...(lastLogin ? { lastLogin } : {}),
  };
}

function requiredString(value: unknown, fieldName: string): string {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`Expected ${fieldName} to be a non-empty string.`);
  }

  return value;
}

function optionalString(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function requiredInteger(value: unknown, fieldName: string): number {
  const integer = optionalInteger(value);

  if (integer === undefined) {
    throw new Error(`Expected ${fieldName} to be an integer.`);
  }

  return integer;
}

function optionalInteger(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isInteger(value)) {
    return value;
  }

  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);

    return Number.isInteger(parsed) ? parsed : undefined;
  }

  return undefined;
}

function optionalISOString(value: unknown): string | undefined {
  if (value instanceof Date) {
    return value.toISOString();
  }

  if (typeof value !== 'string' || value.length === 0) {
    return undefined;
  }

  const timestamp = Date.parse(value);

  if (!Number.isFinite(timestamp)) {
    return value;
  }

  return new Date(timestamp).toISOString();
}
