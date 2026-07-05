-- Run this once against your Postgres database (see README for how).
-- Requires the pgcrypto extension for gen_random_uuid() — most hosted
-- providers (Neon, Supabase, Railway) already have this available; if
-- not, run: CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Cloud-hosted user accounts. This is what makes login/signup and
-- forgot-password work "from anywhere" — the account lives here, not
-- just on one phone's local SQLite database.
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  age INTEGER,
  weight_kg REAL,
  height_cm REAL,
  gender TEXT,
  bio TEXT DEFAULT '',
  photo_path TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Password-reset tokens for the forgot-password flow. Short-lived and
-- single-use — see auth.js for how they're issued/consumed.
CREATE TABLE IF NOT EXISTS password_reset_tokens (
  token TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT false
);

-- WORKED EXAMPLE for syncing app data to the cloud (medicines shown
-- here; the app doesn't call this yet — see medicines.js and the README
-- section "What's cloud-synced vs. what's still local" for the current
-- boundary and how to extend this to appointments/reports/health_records
-- using the same pattern).
CREATE TABLE IF NOT EXISTS medicines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  dosage TEXT,
  instructions TEXT,
  times TEXT,
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,
  frequency TEXT DEFAULT 'daily',
  custom_days TEXT,
  active BOOLEAN DEFAULT true,
  photo_path TEXT,
  prescribed_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
