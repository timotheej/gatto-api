-- ==================================================
-- Photo Performance Indexes
-- ==================================================
-- Created as part of Phase 1 optimizations
-- These indexes optimize the JOIN query in enrichWithPhotos()
-- ==================================================

-- Index on poi_photos.poi_id with status filter
-- Used in: WHERE poi_id IN (...) AND status = 'active'
CREATE INDEX IF NOT EXISTS poi_photos_poi_id_status_idx
ON poi_photos (poi_id, status)
WHERE status = 'active';

-- Index for optimal sorting by primary photo and position
-- Used in: ORDER BY is_primary DESC, position ASC
CREATE INDEX IF NOT EXISTS poi_photos_poi_sort_idx
ON poi_photos (poi_id, is_primary DESC, position ASC)
WHERE status = 'active';

-- Index on poi_photo_variants.photo_id
-- Used in: JOIN ON photo_id
CREATE INDEX IF NOT EXISTS poi_photo_variants_photo_id_idx
ON poi_photo_variants (photo_id);

-- Composite index for variant filtering
-- Used in: WHERE photo_id IN (...) AND variant_key IN (...)
CREATE INDEX IF NOT EXISTS poi_photo_variants_photo_variant_idx
ON poi_photo_variants (photo_id, variant_key);

-- ==================================================
-- Verification queries
-- ==================================================

-- Verify all indexes were created
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('poi_photos', 'poi_photo_variants')
  AND indexname IN (
    'poi_photos_poi_id_status_idx',
    'poi_photos_poi_sort_idx',
    'poi_photo_variants_photo_id_idx',
    'poi_photo_variants_photo_variant_idx'
  );

-- Expected result: 4 rows (one for each index)

-- ==================================================
-- Performance test
-- ==================================================

-- Test query performance with EXPLAIN ANALYZE
EXPLAIN ANALYZE
SELECT
  pp.id as photo_id,
  pp.poi_id,
  pp.dominant_color,
  pp.blurhash,
  pp.is_primary,
  ppv.variant_key,
  ppv.cdn_url,
  ppv.format,
  ppv.width,
  ppv.height
FROM poi_photos pp
LEFT JOIN poi_photo_variants ppv ON ppv.photo_id = pp.id
WHERE pp.poi_id IN (
  SELECT id FROM poi LIMIT 50
)
  AND pp.status = 'active'
  AND ppv.variant_key IN ('card_sq@1x', 'card_sq@2x')
ORDER BY pp.is_primary DESC, pp.position ASC;

-- Expected: Should use the indexes created above
-- Execution time should be < 25ms
