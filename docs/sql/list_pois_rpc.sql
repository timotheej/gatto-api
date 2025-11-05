-- ==================================================
-- RPC: list_pois
-- ==================================================
-- Optimized RPC for map + list view
-- Returns POIs with all necessary data in a single query
-- including scores, ratings, and mentions aggregation
--
-- Based on list_pois_segment but simplified:
-- - No cursor pagination (simple LIMIT)
-- - Mentions aggregation done in SQL (not JavaScript)
-- - Optimized for map bbox queries
-- ==================================================

CREATE OR REPLACE FUNCTION list_pois(
  p_bbox FLOAT[],                       -- [lat_min, lng_min, lat_max, lng_max] (required)
  p_city_slug TEXT DEFAULT 'paris',
  p_primary_types TEXT[] DEFAULT NULL,
  p_subcategories TEXT[] DEFAULT NULL,
  p_neighbourhood_slugs TEXT[] DEFAULT NULL,
  p_district_slugs TEXT[] DEFAULT NULL,
  p_tags_all TEXT[] DEFAULT NULL,       -- AND logic
  p_tags_any TEXT[] DEFAULT NULL,       -- OR logic
  p_awards_providers TEXT[] DEFAULT NULL,
  p_price_min INT DEFAULT NULL,         -- 1-4
  p_price_max INT DEFAULT NULL,         -- 1-4
  p_rating_min NUMERIC DEFAULT NULL,    -- 0-5
  p_rating_max NUMERIC DEFAULT NULL,    -- 0-5
  p_awarded BOOLEAN DEFAULT NULL,
  p_fresh BOOLEAN DEFAULT NULL,
  p_sort TEXT DEFAULT 'gatto',          -- gatto|rating|mentions|price_asc|price_desc
  p_limit INT DEFAULT 50                -- max 80
)
RETURNS TABLE(
  id UUID,
  google_place_id TEXT,
  city_slug TEXT,
  name TEXT,
  name_en TEXT,
  name_fr TEXT,
  slug_en TEXT,
  slug_fr TEXT,
  primary_type TEXT,
  subcategories TEXT[],
  address_street TEXT,
  city TEXT,
  country TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  opening_hours JSONB,
  price_level TEXT,
  price_level_numeric INT,
  phone TEXT,
  website TEXT,
  district_slug TEXT,
  neighbourhood_slug TEXT,
  publishable_status TEXT,
  ai_summary TEXT,
  ai_summary_en TEXT,
  ai_summary_fr TEXT,
  tags JSONB,
  tags_flat TEXT[],
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  -- Scores
  gatto_score NUMERIC,
  digital_score NUMERIC,
  awards_bonus NUMERIC,
  freshness_bonus NUMERIC,
  calculated_at TIMESTAMP,
  -- Rating
  rating_value NUMERIC,
  rating_reviews_count INT,
  -- Mentions
  mentions_count INT,
  mentions_sample JSONB
) AS $$
DECLARE
  v_city_slug TEXT := p_city_slug;
  v_sort TEXT := COALESCE(p_sort, 'gatto');
  v_limit INT := LEAST(GREATEST(p_limit, 1), 80);
BEGIN
  -- Validate bbox
  IF p_bbox IS NULL OR array_length(p_bbox, 1) != 4 THEN
    RAISE EXCEPTION 'bbox is required and must have 4 coordinates: [lat_min, lng_min, lat_max, lng_max]';
  END IF;

  -- Validate bbox bounds
  IF p_bbox[1] < -90 OR p_bbox[3] > 90 OR p_bbox[2] < -180 OR p_bbox[4] > 180 THEN
    RAISE EXCEPTION 'bbox coordinates out of bounds';
  END IF;

  IF p_bbox[1] >= p_bbox[3] OR p_bbox[2] >= p_bbox[4] THEN
    RAISE EXCEPTION 'bbox min must be less than max';
  END IF;

  RETURN QUERY
  WITH
  -- 1) Normalisation paramètres (same as list_pois_segment)
  norm AS (
    SELECT
      v_city_slug AS city_slug,
      CASE WHEN p_primary_types IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_primary_types) AS t(x)) END AS primary_types_lc,
      CASE WHEN p_subcategories IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_subcategories) AS t(x)) END AS subcategories_lc,
      CASE WHEN p_district_slugs IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_district_slugs) AS t(x)) END AS district_slugs_lc,
      CASE WHEN p_neighbourhood_slugs IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_neighbourhood_slugs) AS t(x)) END AS neighbourhood_slugs_lc,
      CASE WHEN p_tags_all IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_all) AS t(x)) END AS tags_all_lc,
      CASE WHEN p_tags_any IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_any) AS t(x)) END AS tags_any_lc,
      CASE WHEN p_awards_providers IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_awards_providers) AS t(x)) END AS awards_providers_lc,
      CASE WHEN p_price_min BETWEEN 1 AND 4 THEN p_price_min ELSE NULL END AS price_min,
      CASE WHEN p_price_max BETWEEN 1 AND 4 THEN p_price_max ELSE NULL END AS price_max,
      CASE WHEN p_rating_min BETWEEN 0 AND 5 THEN p_rating_min ELSE NULL END AS rating_min,
      CASE WHEN p_rating_max BETWEEN 0 AND 5 THEN p_rating_max ELSE NULL END AS rating_max,
      p_bbox AS bbox_valid
  ),

  -- 2) Sources métriques
  scores AS (
    SELECT
      lgs.poi_id,
      lgs.gatto_score     AS sc_gatto_score,
      lgs.digital_score   AS sc_digital_score,
      lgs.awards_bonus    AS sc_awards_bonus,
      lgs.freshness_bonus AS sc_freshness_bonus,
      lgs.calculated_at   AS sc_calculated_at
    FROM public.latest_gatto_scores lgs
  ),
  ratings AS (
    SELECT
      lgr.poi_id,
      lgr.rating_value    AS rt_rating_value,
      lgr.reviews_count   AS rt_reviews_count
    FROM public.latest_google_rating lgr
  ),
  -- 3) Mentions avec aggregation en SQL (optimisation principale)
  mentions AS (
    SELECT
      poi_id,
      COUNT(*)::INT as mt_mentions_count,
      jsonb_agg(
        jsonb_build_object(
          'domain', domain,
          'url', url,
          'title', title,
          'excerpt', excerpt
        ) ORDER BY published_at_guess DESC
      ) FILTER (WHERE rn <= 6) as mt_mentions_sample
    FROM (
      SELECT
        poi_id,
        domain,
        url,
        title,
        excerpt,
        published_at_guess,
        ROW_NUMBER() OVER (PARTITION BY poi_id ORDER BY published_at_guess DESC) as rn
      FROM public.ai_mention
      WHERE ai_decision = 'ACCEPT'
    ) sub
    GROUP BY poi_id
  ),

  -- 4) Base enrichie
  base AS (
    SELECT
      p.id,
      p.google_place_id,
      p.city_slug,
      p.name,
      p.name_en,
      p.name_fr,
      p.slug_en,
      p.slug_fr,
      p.primary_type,
      p.address_street,
      p.city,
      p.country,
      p.lat,
      p.lng,
      p.opening_hours,
      p.price_level,
      p.phone,
      p.website,
      p.district_slug,
      p.neighbourhood_slug,
      p.publishable_status,
      p.ai_summary,
      p.ai_summary_en,
      p.ai_summary_fr,
      p.tags,
      p.subcategories,
      p.created_at,
      p.updated_at,
      -- calculs pour filtres
      lower(p.primary_type::text) AS primary_type_slug,
      (SELECT array_agg(lower(v)) FROM unnest(p.subcategories) AS v) AS subcategories_lc,
      public.tags_to_text_arr_deep(p.tags) AS tags_flat,
      CASE p.price_level
        WHEN 'PRICE_LEVEL_INEXPENSIVE'    THEN 1
        WHEN 'PRICE_LEVEL_MODERATE'       THEN 2
        WHEN 'PRICE_LEVEL_EXPENSIVE'      THEN 3
        WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4
        ELSE NULL
      END AS price_level_numeric,
      lower(p.district_slug)      AS district_slug_lc,
      lower(p.neighbourhood_slug) AS neighbourhood_slug_lc,
      -- awards providers à partir des tags
      COALESCE((
        SELECT array_agg(DISTINCT lower(aw->>'provider'))
        FROM jsonb_array_elements(COALESCE(p.tags->'badges'->'awards','[]'::jsonb)) aw
        WHERE aw ? 'provider'
      ), '{}'::text[]) AS awards_providers,
      -- métriques
      sc.sc_gatto_score     AS gatto_score,
      sc.sc_digital_score   AS digital_score,
      sc.sc_awards_bonus    AS awards_bonus,
      sc.sc_freshness_bonus AS freshness_bonus,
      sc.sc_calculated_at   AS calculated_at,
      COALESCE(rt.rt_rating_value,   0)::numeric AS rating_value,
      COALESCE(rt.rt_reviews_count,  0)          AS rating_reviews_count,
      COALESCE(mt.mt_mentions_count, 0)::integer AS mentions_count,
      COALESCE(mt.mt_mentions_sample, '[]'::jsonb) AS mentions_sample
    FROM public.poi p
    JOIN scores   sc ON sc.poi_id = p.id
    LEFT JOIN ratings  rt ON rt.poi_id = p.id
    LEFT JOIN mentions mt ON mt.poi_id = p.id
    WHERE p.publishable_status = 'eligible'
  ),

  -- 5) Filtres (same as list_pois_segment but bbox is always applied)
  filtered AS (
    SELECT b.*
    FROM base b
    CROSS JOIN norm n
    WHERE
      b.city_slug = n.city_slug
      -- Spatial filtering FIRST (optimization)
      AND b.lat IS NOT NULL AND b.lng IS NOT NULL
      AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
      AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
      -- Other filters
      AND (n.primary_types_lc IS NULL OR b.primary_type_slug = ANY(n.primary_types_lc))
      AND (n.subcategories_lc IS NULL OR (b.subcategories_lc IS NOT NULL AND b.subcategories_lc && n.subcategories_lc))
      AND (n.price_min IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
      AND (n.price_max IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
      AND (n.rating_min IS NULL OR b.rating_value >= n.rating_min)
      AND (n.rating_max IS NULL OR b.rating_value <= n.rating_max)
      AND (n.district_slugs_lc    IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
      AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
      AND (n.tags_all_lc IS NULL OR b.tags_flat @> n.tags_all_lc)
      AND (n.tags_any_lc IS NULL OR b.tags_flat && n.tags_any_lc)
      AND (n.awards_providers_lc IS NULL OR (b.awards_providers && n.awards_providers_lc))
      AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                          OR   (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
      AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                          OR   (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
  ),

  -- 6) Tri stable (same as list_pois_segment)
  sorted AS (
    SELECT
      f.*,
      CASE v_sort
        WHEN 'price_desc' THEN COALESCE(f.price_level_numeric, 0)::numeric
        WHEN 'price_asc'  THEN -COALESCE(f.price_level_numeric, 0)::numeric
        WHEN 'mentions'   THEN f.mentions_count::numeric
        WHEN 'rating'     THEN f.rating_value
        ELSE f.gatto_score
      END AS sort_key
    FROM filtered f
    ORDER BY sort_key DESC NULLS LAST, f.id ASC
  )

  -- 7) Return results (no cursor pagination)
  SELECT
    s.id,
    s.google_place_id::text,
    s.city_slug::text,
    s.name::text,
    s.name_en::text,
    s.name_fr::text,
    s.slug_en::text,
    s.slug_fr::text,
    s.primary_type::text,
    s.subcategories,
    s.address_street::text,
    s.city::text,
    s.country::text,
    s.lat::double precision,
    s.lng::double precision,
    s.opening_hours,
    s.price_level::text,
    s.price_level_numeric,
    s.phone::text,
    s.website::text,
    s.district_slug::text,
    s.neighbourhood_slug::text,
    s.publishable_status::text,
    s.ai_summary::text,
    s.ai_summary_en::text,
    s.ai_summary_fr::text,
    s.tags,
    s.tags_flat,
    s.created_at,
    s.updated_at,
    s.gatto_score,
    s.digital_score,
    s.awards_bonus,
    s.freshness_bonus,
    s.calculated_at,
    s.rating_value,
    s.rating_reviews_count,
    s.mentions_count,
    s.mentions_sample
  FROM sorted s
  LIMIT v_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ==================================================
-- Indexes for optimal performance
-- ==================================================

-- Spatial index for bbox filtering (if not exists)
CREATE INDEX IF NOT EXISTS poi_lat_lng_idx
ON poi (lat, lng);

-- Composite index for common query patterns
CREATE INDEX IF NOT EXISTS poi_map_query_idx
ON poi (publishable_status, city_slug, lat, lng)
WHERE publishable_status = 'eligible';

-- Index for primary_type filtering
CREATE INDEX IF NOT EXISTS poi_primary_type_idx
ON poi (primary_type);

-- GIN index for tags array filtering
CREATE INDEX IF NOT EXISTS poi_tags_idx
ON poi USING GIN (tags);

-- GIN index for subcategories array filtering
CREATE INDEX IF NOT EXISTS poi_subcategories_idx
ON poi USING GIN (subcategories);

-- Index for neighbourhood filtering
CREATE INDEX IF NOT EXISTS poi_neighbourhood_slug_idx
ON poi (neighbourhood_slug);

-- Index for district filtering
CREATE INDEX IF NOT EXISTS poi_district_slug_idx
ON poi (district_slug);

-- Index for price filtering
CREATE INDEX IF NOT EXISTS poi_price_level_numeric_idx
ON poi (price_level_numeric);

-- ==================================================
-- Usage example
-- ==================================================

-- Get 50 restaurants in Paris within a bbox
-- SELECT * FROM list_pois(
--   p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
--   p_city_slug := 'paris',
--   p_primary_types := ARRAY['restaurant'],
--   p_limit := 50
-- );
