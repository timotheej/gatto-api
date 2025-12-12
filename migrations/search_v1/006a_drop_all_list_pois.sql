-- Migration 006a: Drop all existing versions of list_pois
-- Date: 2025-12-12
-- Description: Clean up all list_pois function versions to avoid conflicts
--
-- IMPORTANT: Execute this BEFORE copying list_pois_rpc.sql from docs/sql/
--
-- This ensures no ambiguity errors when creating the new function with
-- additional parameters (p_name_search, p_name_similarity_threshold)

-- ============================================================================
-- DROP ALL VERSIONS OF list_pois
-- ============================================================================

-- Method 1: Drop by specific known signatures
DROP FUNCTION IF EXISTS list_pois(
  FLOAT[], TEXT, TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[],
  INT, INT, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN, TEXT, INT, INT
) CASCADE;

DROP FUNCTION IF EXISTS list_pois(
  FLOAT[], TEXT, TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[],
  INT, INT, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN, TEXT, INT, INT
) CASCADE;

DROP FUNCTION IF EXISTS list_pois(
  FLOAT[], TEXT, TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[], TEXT[],
  INT, INT, NUMERIC, NUMERIC, BOOLEAN, BOOLEAN, TEXT, INT, INT, TEXT
) CASCADE;

-- Method 2: Drop ANY remaining version (catches all cases)
-- This uses a more aggressive approach to ensure complete cleanup
DO $$
DECLARE
  func_record RECORD;
BEGIN
  FOR func_record IN
    SELECT proname, oidvectortypes(proargtypes) as argtypes
    FROM pg_proc
    WHERE proname = 'list_pois'
      AND pg_function_is_visible(oid)
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I(%s) CASCADE',
                   func_record.proname,
                   func_record.argtypes);
    RAISE NOTICE 'Dropped function: %(%)', func_record.proname, func_record.argtypes;
  END LOOP;
END $$;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify that no list_pois functions remain
SELECT
  proname,
  oidvectortypes(proargtypes) as parameters,
  pronargs as num_args
FROM pg_proc
WHERE proname = 'list_pois';

-- Expected: 0 rows (empty result)

-- ============================================================================
-- NEXT STEP
-- ============================================================================
-- After executing this migration:
-- 1. Open docs/sql/list_pois_rpc.sql
-- 2. Copy the ENTIRE content
-- 3. Paste in Supabase SQL Editor and execute
--
-- This will create the new list_pois function with:
--   - p_name_search parameter
--   - p_name_similarity_threshold parameter
--   - name_relevance_score in return type
--   - 'relevance' sort option
