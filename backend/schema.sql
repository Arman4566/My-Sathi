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

-- Cloud sync tables for all of the app's data. Same pattern throughout:
-- id + user_id + the same fields as the local SQLite tables, snake_cased.
-- See cloud_sync_service.dart for how the Flutter app pushes to and
-- pulls from these.
--
-- IMPORTANT LIMITATION: imagePath/filePath/photoPath columns store
-- whatever local device file path the app had at the time (e.g. a
-- prescription photo's cache path). That path is meaningless on a
-- different phone — only the other fields (name, text, OCR text, AI
-- summary, etc.) actually sync usefully across devices right now. Making
-- photos themselves available on every device would need real cloud file
-- storage (e.g. Supabase Storage/S3) in addition to this database — a
-- separate, larger piece of work from what's here.

CREATE TABLE IF NOT EXISTS medicines (
  id UUID PRIMARY KEY,
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

CREATE TABLE IF NOT EXISTS appointments (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  doctor_name TEXT,
  location TEXT,
  date_time TIMESTAMPTZ,
  notes TEXT DEFAULT '',
  reminder_set BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS prescriptions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_path TEXT,
  raw_text TEXT,
  doctor_name TEXT,
  date_added TIMESTAMPTZ,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS medical_reports (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT,
  file_path TEXT,
  raw_text TEXT,
  summary TEXT,
  uploaded_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS health_records (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date TIMESTAMPTZ,
  weight_kg REAL,
  blood_pressure TEXT,
  sugar_level REAL,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
