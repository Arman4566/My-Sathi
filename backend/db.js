// Postgres connection pool. Works with any standard Postgres host —
// Neon, Supabase, Railway, RDS, or your own server. Put the connection
// string in .env as DATABASE_URL (see .env.example).
const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  // Most free-tier hosted Postgres providers (Neon, Supabase, Railway)
  // require SSL and hand you a connection string with sslmode=require.
  // The rejectUnauthorized:false is standard for connecting to these
  // without needing to install their CA certificate locally.
  ssl: process.env.DATABASE_URL?.includes('sslmode=require')
    ? { rejectUnauthorized: false }
    : false,
});

module.exports = pool;
