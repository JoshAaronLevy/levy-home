#!/usr/bin/env node

import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { Pool, neonConfig } from '@neondatabase/serverless';
import dotenv from 'dotenv';
import ws from 'ws';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const apiDirectory = path.resolve(scriptDirectory, '..');
const migrationsDirectory = path.join(apiDirectory, 'migrations');

dotenv.config({ path: path.join(apiDirectory, '.env') });
neonConfig.webSocketConstructor = ws;

const databaseURL = process.env.DATABASE_URL?.trim();

if (!databaseURL) {
  console.error('DATABASE_URL is not configured; cannot run API migrations.');
  process.exit(1);
}

const pool = new Pool({ connectionString: databaseURL });

try {
  const migrationFiles = (await readdir(migrationsDirectory))
    .filter((fileName) => fileName.endsWith('.sql'))
    .sort();

  if (migrationFiles.length === 0) {
    console.log('No API migrations found.');
    process.exit(0);
  }

  const client = await pool.connect();

  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        name TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    `);

    const appliedResult = await client.query('SELECT name FROM schema_migrations');
    const appliedMigrations = new Set(
      appliedResult.rows
        .map((row) => row.name)
        .filter((name) => typeof name === 'string'),
    );

    let appliedCount = 0;
    let skippedCount = 0;

    for (const migrationFile of migrationFiles) {
      if (appliedMigrations.has(migrationFile)) {
        skippedCount += 1;
        continue;
      }

      const migrationPath = path.join(migrationsDirectory, migrationFile);
      const migrationSQL = await readFile(migrationPath, 'utf8');

      console.log(`Applying API migration ${migrationFile}...`);

      try {
        await client.query(migrationSQL);
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
      }

      await client.query(
        'INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT (name) DO NOTHING',
        [migrationFile],
      );

      appliedCount += 1;
    }

    console.log(`API migrations complete. Applied ${appliedCount}; skipped ${skippedCount}.`);
  } finally {
    client.release();
  }
} finally {
  await pool.end();
}
