-- ==================================================
-- Drop list_pois function
-- ==================================================
-- IMPORTANT: Execute this BEFORE running list_pois_rpc.sql
-- PostgreSQL does not change return types with CREATE OR REPLACE
-- ==================================================

-- Drop the function with its full signature
DROP FUNCTION IF EXISTS list_pois(
  double precision[],  -- p_bbox
  text,                -- p_city_slug
  text[],              -- p_primary_types
  text[],              -- p_subcategories
  text[],              -- p_neighbourhood_slugs
  text[],              -- p_district_slugs
  text[],              -- p_tags_all
  text[],              -- p_tags_any
  text[],              -- p_awards_providers
  integer,             -- p_price_min
  integer,             -- p_price_max
  numeric,             -- p_rating_min
  numeric,             -- p_rating_max
  boolean,             -- p_awarded
  boolean,             -- p_fresh
  text,                -- p_sort
  integer              -- p_limit
);

-- Verify the function is dropped
SELECT
  routine_name,
  routine_type
FROM information_schema.routines
WHERE routine_name = 'list_pois'
  AND routine_schema = 'public';

-- Expected result: 0 rows (function deleted)
