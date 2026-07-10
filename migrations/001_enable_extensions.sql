-- Migration 001: Enable extensions
-- Section 1 of pier-supabase-migration-spec.md
-- uuid-ossp for gen_random_uuid, pg_trgm for fuzzy search, pgvector for
-- embedding similarity in dedup, pgcrypto for random tokens.
-- Note: pg_cron is Supabase-managed (dashboard Extensions tab, V1.1), not here.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
