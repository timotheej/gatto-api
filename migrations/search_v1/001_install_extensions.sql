-- Migration 001: Install required PostgreSQL extensions for fuzzy search
-- Date: 2025-12-11
-- Description: Install pg_trgm (trigram) and unaccent extensions

-- Enable trigram extension for fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable unaccent extension for accent removal
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Verification query
-- Run this after executing to confirm installation:
-- SELECT extname, extversion FROM pg_extension WHERE extname IN ('pg_trgm', 'unaccent');

-- Test query to verify trigram functionality:
-- SELECT
--   similarity('Le Comptoir', 'comptoir') AS test_exact,
--   similarity('Le Comptoir', 'comptoar') AS test_typo,
--   similarity('Le Comptoir', 'italien') AS test_no_match;
-- Expected: test_exact ≈ 0.4-0.5, test_typo ≈ 0.3-0.4, test_no_match ≈ 0.0-0.1
