-- Migration 005: Create autocomplete_search RPC function
-- Date: 2025-12-11
-- Description: Fast autocomplete for search bar suggestions
--              Returns POIs + Types matching the query

-- ============================================================================
-- RPC: autocomplete_search
-- ============================================================================
-- Purpose: Provide real-time autocomplete suggestions
--
-- Returns 5 types of results:
--   1. POIs matching by name (fuzzy)
--   2. Types matching via detection keywords (prefix match)
--   3. Parent categories (e.g., "restaurant")
--   4. Multi-word matching (e.g., "restaurant italien")
--   5. Types matching via labels (fuzzy fallback)
--
-- Example usage:
--   SELECT * FROM autocomplete_search('ital', 'paris', 'fr', 10);
--
-- Returns (sorted by relevance DESC):
--   type              | value                                  | display                          | relevance
--   ------------------|----------------------------------------|----------------------------------|----------
--   type              | italian_restaurant                     | Restaurant italien (type)        | 0.98
--   parent_category   | parent:restaurant                      | Restaurant (catégorie)           | 0.95
--   poi               | 123e4567-e89b-12d3-a456-426614174000  | L'Italiano · Restaurant italien  | 0.7
--   poi               | 223e4567-e89b-12d3-a456-426614174001  | Pizza Italiana · Pizzeria        | 0.65
-- ============================================================================

CREATE OR REPLACE FUNCTION autocomplete_search(
  p_query TEXT,
  p_city_slug TEXT DEFAULT 'paris',
  p_lang TEXT DEFAULT 'fr',
  p_limit INT DEFAULT 10
)
RETURNS TABLE(
  type TEXT,
  value TEXT,
  display TEXT,
  relevance FLOAT
) AS $$
BEGIN
  RETURN QUERY

  WITH
  -- Split query into words for multi-word matching
  query_words AS (
    SELECT unnest(string_to_array(lower(trim(p_query)), ' ')) AS word
  ),
  all_results AS (
    -- ===========================================================================
    -- 1. POIs matching by name (fuzzy with trigram similarity)
    -- ===========================================================================
    SELECT
      'poi'::TEXT AS type,
      p.id::TEXT AS value,
      (p.name || ' · ' || COALESCE(p.primary_type, 'POI'))::TEXT AS display,
      similarity(p.name_normalized, normalize_for_search(p_query)) AS relevance
    FROM poi p
    WHERE p.city_slug = p_city_slug
      AND p.publishable_status = 'eligible'
      AND similarity(p.name_normalized, normalize_for_search(p_query)) > 0.3

    UNION ALL

    -- ===========================================================================
    -- 2. Types via detection keywords (prefix match - fast and relevant)
    -- ===========================================================================
    -- Example: "ital" matches keyword "italien" → italian_restaurant
    -- Uses existing detection_keywords_fr/en arrays from poi_types table
    SELECT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      (
        CASE
          WHEN p_lang = 'en' THEN pt.label_en
          ELSE pt.label_fr
        END || ' (type)'
      )::TEXT AS display,
      -- Relevance: closer to query length = higher score
      -- "ital" (4 chars) vs "italien" (7 chars) → 1.0 - (3/10) = 0.7
      (1.0 - LEAST(LENGTH(keyword) - LENGTH(p_query), 5)::FLOAT / 10.0) AS relevance
    FROM poi_types pt,
         LATERAL UNNEST(
           CASE
             WHEN p_lang = 'en' THEN pt.detection_keywords_en
             ELSE pt.detection_keywords_fr
           END
         ) AS keyword
    WHERE pt.is_active = true
      AND keyword LIKE (lower(p_query) || '%')  -- Prefix match

    UNION ALL

    -- ===========================================================================
    -- 3. Parent categories (e.g., "restaurant", "cafe")
    -- ===========================================================================
    SELECT DISTINCT
      'parent_category'::TEXT AS type,
      ('parent:' || pt.parent_category)::TEXT AS value,  -- Prefix to avoid conflicts with type_keys
      (
        CASE
          WHEN p_lang = 'en' THEN initcap(pt.parent_category)
          ELSE initcap(pt.parent_category)
        END || ' (catégorie)'
      )::TEXT AS display,
      0.95::FLOAT AS relevance  -- High relevance for parent category matches
    FROM poi_types pt
    WHERE pt.is_active = true
      AND pt.parent_category IS NOT NULL
      AND pt.parent_category LIKE (lower(p_query) || '%')  -- Prefix match on parent category

    UNION ALL

    -- ===========================================================================
    -- 4. Multi-word matching (e.g., "restaurant italien")
    -- ===========================================================================
    -- Matches types where parent_category + keyword match different words in query
    SELECT DISTINCT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      (
        CASE
          WHEN p_lang = 'en' THEN pt.label_en
          ELSE pt.label_fr
        END || ' (type)'
      )::TEXT AS display,
      0.98::FLOAT AS relevance  -- Very high relevance for multi-word exact matches
    FROM poi_types pt,
         query_words qw,
         LATERAL UNNEST(
           CASE
             WHEN p_lang = 'en' THEN pt.detection_keywords_en
             ELSE pt.detection_keywords_fr
           END
         ) AS keyword
    WHERE pt.is_active = true
      AND pt.parent_category IS NOT NULL
      -- One word matches parent_category
      AND EXISTS (
        SELECT 1 FROM query_words
        WHERE word = pt.parent_category
      )
      -- Another word matches a keyword
      AND keyword = qw.word
      AND keyword != pt.parent_category  -- Ensure it's a different word

    UNION ALL

    -- ===========================================================================
    -- 5. Types via labels (fuzzy match - strict fallback)
    -- ===========================================================================
    -- Only for single-word queries to avoid false positives
    -- Disabled for multi-word queries (handled by section 4)
    SELECT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      (
        CASE
          WHEN p_lang = 'en' THEN pt.label_en
          ELSE pt.label_fr
        END || ' (type)'
      )::TEXT AS display,
      similarity(
        CASE WHEN p_lang = 'en' THEN pt.label_en ELSE pt.label_fr END,
        p_query
      ) AS relevance
    FROM poi_types pt
    WHERE pt.is_active = true
      AND position(' ' in p_query) = 0  -- Only for single-word queries
      AND similarity(
        CASE WHEN p_lang = 'en' THEN pt.label_en ELSE pt.label_fr END,
        p_query
      ) > 0.6  -- Stricter threshold to avoid false positives
  )
  -- ===========================================================================
  -- DEDUPLICATION AND ORDERING
  -- ===========================================================================
  -- Use DISTINCT ON to keep only the highest relevance score for each (type, value)
  -- Then sort final results by relevance
  SELECT
    deduped.type,
    deduped.value,
    deduped.display,
    deduped.relevance
  FROM (
    SELECT DISTINCT ON (all_results.type, all_results.value)
      all_results.type,
      all_results.value,
      all_results.display,
      all_results.relevance
    FROM all_results
    ORDER BY
      all_results.type,
      all_results.value,
      all_results.relevance DESC    -- Keep highest relevance for each (type, value)
  ) deduped
  ORDER BY
    deduped.relevance DESC,          -- Sort by relevance (highest first)
    deduped.type DESC                 -- Then by type (types/parent_category before POIs)
  LIMIT p_limit;

END;
$$ LANGUAGE plpgsql STABLE;


-- ============================================================================
-- PERFORMANCE NOTES
-- ============================================================================
-- Expected query time: < 50ms (slightly slower due to multi-word logic)
--
-- Indexes used:
--   - poi_name_normalized_trgm_idx (for POI fuzzy match)
--   - No index needed for types (small table, UNNEST + LIKE is fast)
--
-- Optimizations:
--   - LIMIT applied early via ORDER BY
--   - DISTINCT ON for deduplication (keeps highest relevance)
--   - Prefix match (LIKE 'query%') faster than contains (LIKE '%query%')
--   - LATERAL UNNEST for efficient array expansion
--   - Multi-word splitting with query_words CTE for intelligent matching
--   - Section 5 (labels) disabled for multi-word queries to avoid false positives
--
-- Query types handled:
--   - Single word: "italien" → matches keywords + parent categories + labels
--   - Multi-word: "restaurant italien" → matches parent_category + keyword
--   - POI names: "comptoir" → fuzzy match on POI names
-- ============================================================================


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Test 1: Search for Italian
-- SELECT * FROM autocomplete_search('ital', 'paris', 'fr', 10);
-- Expected: italian_restaurant type + POIs with "Ital" in name

-- Test 2: Search for sushi
-- SELECT * FROM autocomplete_search('sush', 'paris', 'fr', 10);
-- Expected: japanese_restaurant type + sushi POIs

-- Test 3: Search for specific POI
-- SELECT * FROM autocomplete_search('comptoir', 'paris', 'fr', 10);
-- Expected: POIs with "Comptoir" in name

-- Test 4: Performance test
-- EXPLAIN ANALYZE
-- SELECT * FROM autocomplete_search('rest', 'paris', 'fr', 10);
-- Expected: < 30ms

-- Test 5: Edge case - very short query
-- SELECT * FROM autocomplete_search('ca', 'paris', 'fr', 10);
-- Expected: Cafes + types starting with 'ca'

-- Test 6: Multi-word query
-- SELECT * FROM autocomplete_search('restaurant italien', 'paris', 'fr', 10);
-- Expected: italian_restaurant at the top (relevance 0.98)

-- Test 7: Parent category only
-- SELECT * FROM autocomplete_search('restaurant', 'paris', 'fr', 10);
-- Expected: 'restaurant' parent category (relevance 0.95) + related types
