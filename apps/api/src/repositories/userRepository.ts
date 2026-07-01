import type { LevyHomeUser } from '../contracts.js';
import { getDatabaseClient, type DatabaseQuery } from '../db/client.js';
import { optionalISOString, optionalString, requiredInteger, requiredString } from '../db/rowReaders.js';

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
