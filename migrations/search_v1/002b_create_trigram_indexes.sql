-- Migration 002b: Create trigram indexes (PART 2 - Slower)
-- Date: 2025-12-11
-- Description: Create GIN trigram indexes for fuzzy search
-- Duration: ~30-60 seconds (depends on number of POIs)
-- Note: Without CONCURRENTLY to avoid timeout in Supabase SQL Editor

-- ============================================================================
-- CREATE TRIGRAM INDEXES (GIN type)
-- ============================================================================

-- Index on name_normalized (main search field)
CREATE INDEX IF NOT EXISTS poi_name_normalized_trgm_idx
ON poi USING GIN (name_normalized gin_trgm_ops);

-- Index on name_fr_normalized (French name search)
CREATE INDEX IF NOT EXISTS poi_name_fr_normalized_trgm_idx
ON poi USING GIN (name_fr_normalized gin_trgm_ops);

-- Index on name_en_normalized (English name search)
CREATE INDEX IF NOT EXISTS poi_name_en_normalized_trgm_idx
ON poi USING GIN (name_en_normalized gin_trgm_ops);


-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Check indexes were created:
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE tablename = 'poi'
--   AND indexname LIKE '%trgm%';

-- Test fuzzy search performance:
-- EXPLAIN ANALYZE
-- SELECT name, similarity(name_normalized, 'comptoir') AS sim
-- FROM poi
-- WHERE similarity(name_normalized, 'comptoir') > 0.3
-- ORDER BY sim DESC
-- LIMIT 20;
-- Expected: Uses "Bitmap Index Scan" on poi_name_normalized_trgm_idx
