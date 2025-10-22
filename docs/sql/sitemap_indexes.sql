-- ==================================================
-- Sitemap Indexes
-- ==================================================
-- These indexes optimize the performance of the /v1/sitemap/pois endpoint
-- by improving filter and order operations on the poi table.
-- 
-- Note: latest_gatto_scores is a view and will automatically use indexes
-- from its underlying source tables.
--
-- Run this migration in your Supabase SQL editor to create the indexes.
-- ==================================================

-- Index for filtering POIs by publishable_status
-- Improves WHERE publishable_status = 'eligible' performance
CREATE INDEX IF NOT EXISTS poi_publishable_status_idx 
ON poi (publishable_status);

-- Index for ordering POIs by updated_at in descending order
-- Improves ORDER BY updated_at DESC performance
CREATE INDEX IF NOT EXISTS poi_updated_at_idx 
ON poi (updated_at DESC);

-- Note: latest_gatto_scores is a VIEW, not a table
-- Indexes should be created on the underlying source table(s) that feed the view
-- The view will automatically benefit from indexes on its source tables

-- Composite index for the sitemap query pattern
-- Optimizes the combined filter + order operation
CREATE INDEX IF NOT EXISTS poi_sitemap_idx 
ON poi (publishable_status, updated_at DESC) 
WHERE publishable_status = 'eligible';

