-- Migration 008: Update autocomplete_search RPC for optimized UI response
-- Date: 2025-12-12
-- Description: Add POI metadata (slug, district, city, type_label) for better UX

-- ============================================================================
-- DROP AND RECREATE autocomplete_search with new columns
-- ============================================================================

DROP FUNCTION IF EXISTS autocomplete_search(TEXT, TEXT, TEXT, INT);

CREATE OR REPLACE FUNCTION autocomplete_search(
  p_query TEXT,
  p_city_slug TEXT DEFAULT 'paris',
  p_lang TEXT DEFAULT 'fr',
  p_limit INT DEFAULT 7  -- Reduced to 7 (Hick's Law)
)
RETURNS TABLE(
  type TEXT,
  value TEXT,
  display TEXT,
  relevance FLOAT,
  -- New fields for POIs
  poi_slug TEXT,
  poi_type_label TEXT,
  poi_district TEXT,
  poi_city TEXT
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
      p.name::TEXT AS display,  -- Just name (no " · type")
      similarity(p.name_normalized, normalize_for_search(p_query)) AS relevance,
      -- POI metadata
      p.slug::TEXT AS poi_slug,
      CASE
        WHEN p_lang = 'en' THEN pt.label_en
        ELSE pt.label_fr
      END AS poi_type_label,
      CASE
        WHEN ua.name LIKE '%Arrondissement' THEN regexp_replace(ua.name, 'Paris (\d+)e? Arrondissement', '\1e arr.')
        ELSE ua.name
      END AS poi_district,
      'Paris'::TEXT AS poi_city
    FROM poi p
    LEFT JOIN poi_types pt ON p.primary_type = pt.type_key
    LEFT JOIN urban_areas ua ON p.district_id = ua.id
    WHERE p.city_slug = p_city_slug
      AND p.publishable_status = 'eligible'
      AND similarity(p.name_normalized, normalize_for_search(p_query)) > 0.3

    UNION ALL

    -- ===========================================================================
    -- 2. Types via detection keywords (prefix match)
    -- ===========================================================================
    SELECT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      CASE
        WHEN p_lang = 'en' THEN pt.label_en
        ELSE pt.label_fr
      END AS display,  -- No "(type)" suffix
      (1.0 - LEAST(LENGTH(keyword) - LENGTH(p_query), 5)::FLOAT / 10.0) AS relevance,
      NULL::TEXT AS poi_slug,
      NULL::TEXT AS poi_type_label,
      NULL::TEXT AS poi_district,
      NULL::TEXT AS poi_city
    FROM poi_types pt,
         LATERAL UNNEST(
           CASE
             WHEN p_lang = 'en' THEN pt.detection_keywords_en
             ELSE pt.detection_keywords_fr
           END
         ) AS keyword
    WHERE pt.is_active = true
      AND keyword LIKE (lower(p_query) || '%')

    UNION ALL

    -- ===========================================================================
    -- 3. Parent categories
    -- ===========================================================================
    SELECT DISTINCT
      'type'::TEXT AS type,
      ('parent:' || pt.parent_category)::TEXT AS value,
      initcap(pt.parent_category)::TEXT AS display,  -- No "(catégorie)" suffix
      0.95::FLOAT AS relevance,
      NULL::TEXT AS poi_slug,
      NULL::TEXT AS poi_type_label,
      NULL::TEXT AS poi_district,
      NULL::TEXT AS poi_city
    FROM poi_types pt
    WHERE pt.is_active = true
      AND pt.parent_category IS NOT NULL
      AND pt.parent_category LIKE (lower(p_query) || '%')

    UNION ALL

    -- ===========================================================================
    -- 4. Multi-word matching
    -- ===========================================================================
    SELECT DISTINCT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      CASE
        WHEN p_lang = 'en' THEN pt.label_en
        ELSE pt.label_fr
      END AS display,
      0.98::FLOAT AS relevance,
      NULL::TEXT AS poi_slug,
      NULL::TEXT AS poi_type_label,
      NULL::TEXT AS poi_district,
      NULL::TEXT AS poi_city
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
      AND EXISTS (
        SELECT 1 FROM query_words
        WHERE word = pt.parent_category
      )
      AND keyword = qw.word
      AND keyword != pt.parent_category

    UNION ALL

    -- ===========================================================================
    -- 5. Types via labels (fuzzy fallback)
    -- ===========================================================================
    SELECT
      'type'::TEXT AS type,
      pt.type_key::TEXT AS value,
      CASE
        WHEN p_lang = 'en' THEN pt.label_en
        ELSE pt.label_fr
      END AS display,
      similarity(
        CASE WHEN p_lang = 'en' THEN pt.label_en ELSE pt.label_fr END,
        p_query
      ) AS relevance,
      NULL::TEXT AS poi_slug,
      NULL::TEXT AS poi_type_label,
      NULL::TEXT AS poi_district,
      NULL::TEXT AS poi_city
    FROM poi_types pt
    WHERE pt.is_active = true
      AND position(' ' in p_query) = 0
      AND similarity(
        CASE WHEN p_lang = 'en' THEN pt.label_en ELSE pt.label_fr END,
        p_query
      ) > 0.6
  )
  SELECT
    deduped.type,
    deduped.value,
    deduped.display,
    deduped.relevance,
    deduped.poi_slug,
    deduped.poi_type_label,
    deduped.poi_district,
    deduped.poi_city
  FROM (
    SELECT DISTINCT ON (all_results.type, all_results.value)
      all_results.type,
      all_results.value,
      all_results.display,
      all_results.relevance,
      all_results.poi_slug,
      all_results.poi_type_label,
      all_results.poi_district,
      all_results.poi_city
    FROM all_results
    ORDER BY
      all_results.type,
      all_results.value,
      all_results.relevance DESC
  ) deduped
  ORDER BY
    deduped.relevance DESC,
    deduped.type DESC
  LIMIT p_limit;

END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Test with Italian
-- SELECT * FROM autocomplete_search('italien', 'paris', 'fr', 7);
-- Expected: type suggestions without "(type)" + POIs with slug, district, etc.
