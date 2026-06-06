const path = require("node:path");
const Database = require("better-sqlite3");

const root = path.resolve(__dirname, "..");
const stateColumns = ["wishlisted", "available", "seen"];

function normalizeSeriesState(input = {}) {
  return {
    wishlisted: input.wishlisted === true || input.wishlisted === 1,
    available: input.available === true || input.available === 1,
    seen: input.seen === true || input.seen === 1,
  };
}

function hasAnyState(state) {
  return stateColumns.some((key) => state[key]);
}

function rowToState(row) {
  return {
    wishlisted: Boolean(row.wishlisted),
    available: Boolean(row.available),
    seen: Boolean(row.seen),
    updatedAt: row.updated_at,
  };
}

function createLocalSeriesStateStore(options = {}) {
  const dbPath = options.dbPath || process.env.SERIES_STATE_DB || path.join(root, "series_user_state.db");
  const db = new Database(dbPath);
  db.pragma("journal_mode = WAL");
  db.exec(`
    CREATE TABLE IF NOT EXISTS series_user_state (
      imdb_id TEXT PRIMARY KEY,
      wishlisted INTEGER NOT NULL DEFAULT 0,
      available INTEGER NOT NULL DEFAULT 0,
      seen INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );
  `);

  const selectAll = db.prepare(`
    SELECT imdb_id, wishlisted, available, seen, updated_at
    FROM series_user_state
    WHERE wishlisted = 1 OR available = 1 OR seen = 1
    ORDER BY imdb_id ASC
  `);
  const upsert = db.prepare(`
    INSERT INTO series_user_state (imdb_id, wishlisted, available, seen, updated_at)
    VALUES (@id, @wishlisted, @available, @seen, @updatedAt)
    ON CONFLICT(imdb_id) DO UPDATE SET
      wishlisted = excluded.wishlisted,
      available = excluded.available,
      seen = excluded.seen,
      updated_at = excluded.updated_at
  `);
  const remove = db.prepare("DELETE FROM series_user_state WHERE imdb_id = ?");

  return {
    getAll() {
      return Object.fromEntries(selectAll.all().map((row) => [row.imdb_id, rowToState(row)]));
    },
    set(id, input) {
      const state = normalizeSeriesState(input);
      const updatedAt = new Date().toISOString();
      if (!hasAnyState(state)) {
        remove.run(id);
        return { id, ...state, updatedAt };
      }
      upsert.run({
        id,
        wishlisted: state.wishlisted ? 1 : 0,
        available: state.available ? 1 : 0,
        seen: state.seen ? 1 : 0,
        updatedAt,
      });
      return { id, ...state, updatedAt };
    },
    close() {
      db.close();
    },
  };
}

let postgresPool = null;
let postgresReady = null;

function getPostgresConnectionString() {
  return process.env.DATABASE_URL || process.env.POSTGRES_URL || process.env.POSTGRES_PRISMA_URL || "";
}

function createPostgresSeriesStateStore(connectionString = getPostgresConnectionString()) {
  if (!connectionString) {
    const error = new Error("Missing DATABASE_URL or POSTGRES_URL for series state storage.");
    error.statusCode = 503;
    throw error;
  }

  const { Pool } = require("pg");
  if (!postgresPool) {
    postgresPool = new Pool({
      connectionString,
      ssl: connectionString.includes("localhost") ? undefined : { rejectUnauthorized: false },
    });
  }

  async function ensureSchema() {
    if (!postgresReady) {
      postgresReady = postgresPool.query(`
        CREATE TABLE IF NOT EXISTS series_user_state (
          imdb_id TEXT PRIMARY KEY,
          wishlisted BOOLEAN NOT NULL DEFAULT FALSE,
          available BOOLEAN NOT NULL DEFAULT FALSE,
          seen BOOLEAN NOT NULL DEFAULT FALSE,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
    }
    await postgresReady;
  }

  return {
    async getAll() {
      await ensureSchema();
      const result = await postgresPool.query(`
        SELECT imdb_id, wishlisted, available, seen, updated_at
        FROM series_user_state
        WHERE wishlisted = TRUE OR available = TRUE OR seen = TRUE
        ORDER BY imdb_id ASC
      `);
      return Object.fromEntries(result.rows.map((row) => [row.imdb_id, rowToState(row)]));
    },
    async set(id, input) {
      await ensureSchema();
      const state = normalizeSeriesState(input);
      const updatedAt = new Date().toISOString();
      if (!hasAnyState(state)) {
        await postgresPool.query("DELETE FROM series_user_state WHERE imdb_id = $1", [id]);
        return { id, ...state, updatedAt };
      }
      const result = await postgresPool.query(`
        INSERT INTO series_user_state (imdb_id, wishlisted, available, seen, updated_at)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT(imdb_id) DO UPDATE SET
          wishlisted = EXCLUDED.wishlisted,
          available = EXCLUDED.available,
          seen = EXCLUDED.seen,
          updated_at = EXCLUDED.updated_at
        RETURNING imdb_id, wishlisted, available, seen, updated_at
      `, [id, state.wishlisted, state.available, state.seen, updatedAt]);
      return { id: result.rows[0].imdb_id, ...rowToState(result.rows[0]) };
    },
  };
}

function createSeriesStateStore() {
  if (getPostgresConnectionString()) return createPostgresSeriesStateStore();
  if (process.env.VERCEL === "1") {
    return createPostgresSeriesStateStore("");
  }
  return createLocalSeriesStateStore();
}

module.exports = {
  createLocalSeriesStateStore,
  createPostgresSeriesStateStore,
  createSeriesStateStore,
  normalizeSeriesState,
};
