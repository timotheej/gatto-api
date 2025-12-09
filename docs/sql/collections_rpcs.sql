-- ==================================================
-- Drop existing functions first (to avoid signature conflicts)
-- ==================================================

DROP FUNCTION IF EXISTS list_collections(TEXT, INT, INT);
DROP FUNCTION IF EXISTS get_collection_pois(TEXT, INT, INT);

-- ==================================================
-- RPC: list_collections
-- ==================================================
-- Lists all collections for a given city with pagination
-- Returns collections with cover photo info
-- ==================================================

CREATE OR REPLACE FUNCTION list_collections(
  p_city_slug TEXT,                     -- required
  p_limit INT DEFAULT 20,               -- max 100
  p_page INT DEFAULT 1                  -- page number (starts at 1)
)
RETURNS TABLE(
  id UUID,
  slug_fr TEXT,
  slug_en TEXT,
  title_fr TEXT,
  title_en TEXT,
  city_slug TEXT,
  is_dynamic BOOLEAN,
  rules_json JSONB,
  rules_canon JSONB,
  source TEXT,
  content_version INT,
  temporal_strategy TEXT,
  active_period JSONB,
  status TEXT,
  published_at TIMESTAMPTZ,
  last_refresh_at TIMESTAMPTZ,
  auto_refresh_enabled BOOLEAN,
  refresh_cadence_days INT,
  metadata JSONB,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  -- Cover photo
  cover_photo_id UUID,
  cover_photo_cdn_url TEXT,
  cover_photo_format TEXT,
  cover_photo_width INT,
  cover_photo_height INT,
  cover_photo_dominant_color TEXT,
  cover_photo_blurhash TEXT,
  -- Pagination
  total_count BIGINT
) AS $$
DECLARE
  v_limit INT := LEAST(GREATEST(p_limit, 1), 100);  -- max 100 items per page
  v_page INT := GREATEST(p_page, 1);                 -- ensure page >= 1
  v_offset INT := (v_page - 1) * v_limit;            -- calculate offset
BEGIN
  -- Validate city_slug
  IF p_city_slug IS NULL OR p_city_slug = '' THEN
    RAISE EXCEPTION 'city_slug is required';
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.slug_fr,
    c.slug_en,
    c.title_fr,
    c.title_en,
    c.city_slug,
    c.is_dynamic,
    c.rules_json,
    c.rules_canon,
    c.source,
    c.content_version,
    c.temporal_strategy,
    c.active_period,
    c.status,
    c.published_at,
    c.last_refresh_at,
    c.auto_refresh_enabled,
    c.refresh_cadence_days,
    c.metadata,
    c.created_at,
    c.updated_at,
    -- Cover photo
    c.cover_photo_id,
    p.cdn_url AS cover_photo_cdn_url,
    p.format AS cover_photo_format,
    p.width AS cover_photo_width,
    p.height AS cover_photo_height,
    p.dominant_color AS cover_photo_dominant_color,
    p.blurhash AS cover_photo_blurhash,
    -- Total count
    COUNT(*) OVER() AS total_count
  FROM public.collection c
  LEFT JOIN public.poi_photos p ON p.id = c.cover_photo_id
  WHERE c.city_slug = p_city_slug
    AND c.status = 'published'  -- Only return published collections
  ORDER BY c.published_at DESC NULLS LAST, c.updated_at DESC, c.id ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$ LANGUAGE plpgsql STABLE;


-- ==================================================
-- RPC: get_collection_pois
-- ==================================================
-- Gets a collection and all its POIs with full details
-- Accepts both slug_fr and slug_en
-- Returns POIs with same structure as list_pois
-- ==================================================

CREATE OR REPLACE FUNCTION get_collection_pois(
  p_slug TEXT,                          -- collection slug (fr or en)
  p_limit INT DEFAULT 50,               -- max 100
  p_page INT DEFAULT 1                  -- page number (starts at 1)
)
RETURNS TABLE(
  -- Collection info
  collection_id UUID,
  collection_slug_fr TEXT,
  collection_slug_en TEXT,
  collection_title_fr TEXT,
  collection_title_en TEXT,
  collection_city_slug TEXT,
  collection_is_dynamic BOOLEAN,
  collection_rules_json JSONB,
  collection_rules_canon JSONB,
  collection_source TEXT,
  collection_content_version INT,
  collection_temporal_strategy TEXT,
  collection_active_period JSONB,
  collection_status TEXT,
  collection_published_at TIMESTAMPTZ,
  collection_last_refresh_at TIMESTAMPTZ,
  collection_auto_refresh_enabled BOOLEAN,
  collection_refresh_cadence_days INT,
  collection_metadata JSONB,
  collection_created_at TIMESTAMPTZ,
  collection_updated_at TIMESTAMPTZ,
  -- Collection cover photo
  collection_cover_photo_id UUID,
  collection_cover_photo_cdn_url TEXT,
  collection_cover_photo_format TEXT,
  collection_cover_photo_width INT,
  collection_cover_photo_height INT,
  collection_cover_photo_dominant_color TEXT,
  collection_cover_photo_blurhash TEXT,
  -- POI info (same as list_pois)
  poi_id UUID,
  poi_google_place_id TEXT,
  poi_city_slug TEXT,
  poi_name TEXT,
  poi_name_en TEXT,
  poi_name_fr TEXT,
  poi_slug_en TEXT,
  poi_slug_fr TEXT,
  poi_primary_type TEXT,
  poi_subcategories TEXT[],
  poi_address_street TEXT,
  poi_city TEXT,
  poi_country TEXT,
  poi_lat DOUBLE PRECISION,
  poi_lng DOUBLE PRECISION,
  poi_opening_hours JSONB,
  poi_price_level TEXT,
  poi_price_level_numeric INT,
  poi_phone TEXT,
  poi_website TEXT,
  poi_district_slug TEXT,
  poi_neighbourhood_slug TEXT,
  poi_publishable_status TEXT,
  poi_ai_summary TEXT,
  poi_ai_summary_en TEXT,
  poi_ai_summary_fr TEXT,
  poi_tags JSONB,
  poi_tags_flat TEXT[],
  poi_created_at TIMESTAMPTZ,
  poi_updated_at TIMESTAMPTZ,
  -- POI Scores
  poi_gatto_score NUMERIC,
  poi_digital_score NUMERIC,
  poi_awards_bonus NUMERIC,
  poi_freshness_bonus NUMERIC,
  poi_calculated_at TIMESTAMPTZ,
  -- POI Rating
  poi_rating_value NUMERIC,
  poi_rating_reviews_count INT,
  -- POI Mentions
  poi_mentions_count INT,
  poi_mentions_sample JSONB,
  -- Collection item specific
  collection_position INT,
  collection_reason TEXT,
  -- Pagination
  total_count BIGINT
) AS $$
DECLARE
  v_limit INT := LEAST(GREATEST(p_limit, 1), 100);  -- max 100 items per page
  v_page INT := GREATEST(p_page, 1);                 -- ensure page >= 1
  v_offset INT := (v_page - 1) * v_limit;            -- calculate offset
  v_collection_id UUID;
BEGIN
  -- Validate slug
  IF p_slug IS NULL OR p_slug = '' THEN
    RAISE EXCEPTION 'slug is required';
  END IF;

  -- Find collection by slug (accept both fr and en)
  SELECT id INTO v_collection_id
  FROM public.collection
  WHERE slug_fr = p_slug OR slug_en = p_slug
  LIMIT 1;

  -- Check if collection exists
  IF v_collection_id IS NULL THEN
    RAISE EXCEPTION 'Collection not found';
  END IF;

  RETURN QUERY
  WITH
  -- Scores
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
  -- Ratings
  ratings AS (
    SELECT
      lgr.poi_id,
      lgr.rating_value    AS rt_rating_value,
      lgr.reviews_count   AS rt_reviews_count
    FROM public.latest_google_rating lgr
  ),
  -- Mentions
  mentions AS (
    SELECT
      sub.poi_id,
      COUNT(*)::INT as mt_mentions_count,
      jsonb_agg(
        jsonb_build_object(
          'domain', sub.domain,
          'url', sub.url,
          'title', sub.title,
          'excerpt', sub.excerpt
        ) ORDER BY sub.published_at_guess DESC
      ) FILTER (WHERE sub.rn <= 6) as mt_mentions_sample
    FROM (
      SELECT
        am.poi_id,
        am.domain,
        am.url,
        am.title,
        am.excerpt,
        am.published_at_guess,
        ROW_NUMBER() OVER (PARTITION BY am.poi_id ORDER BY am.published_at_guess DESC) as rn
      FROM public.ai_mention am
      WHERE am.ai_decision = 'ACCEPT'
    ) sub
    GROUP BY sub.poi_id
  ),
  -- Collection with cover photo
  coll AS (
    SELECT
      c.id,
      c.slug_fr,
      c.slug_en,
      c.title_fr,
      c.title_en,
      c.city_slug,
      c.is_dynamic,
      c.rules_json,
      c.rules_canon,
      c.source,
      c.content_version,
      c.temporal_strategy,
      c.active_period,
      c.status,
      c.published_at,
      c.last_refresh_at,
      c.auto_refresh_enabled,
      c.refresh_cadence_days,
      c.metadata,
      c.created_at,
      c.updated_at,
      c.cover_photo_id,
      cp.cdn_url AS cover_photo_cdn_url,
      cp.format AS cover_photo_format,
      cp.width AS cover_photo_width,
      cp.height AS cover_photo_height,
      cp.dominant_color AS cover_photo_dominant_color,
      cp.blurhash AS cover_photo_blurhash
    FROM public.collection c
    LEFT JOIN public.poi_photos cp ON cp.id = c.cover_photo_id
    WHERE c.id = v_collection_id
      AND c.status = 'published'  -- Only return published collections
  )
  -- Main query: Join POIs from collection_item
  SELECT
    -- Collection info
    coll.id,
    coll.slug_fr,
    coll.slug_en,
    coll.title_fr,
    coll.title_en,
    coll.city_slug,
    coll.is_dynamic,
    coll.rules_json,
    coll.rules_canon,
    coll.source,
    coll.content_version,
    coll.temporal_strategy,
    coll.active_period,
    coll.status,
    coll.published_at,
    coll.last_refresh_at,
    coll.auto_refresh_enabled,
    coll.refresh_cadence_days,
    coll.metadata,
    coll.created_at,
    coll.updated_at,
    coll.cover_photo_id,
    coll.cover_photo_cdn_url,
    coll.cover_photo_format,
    coll.cover_photo_width,
    coll.cover_photo_height,
    coll.cover_photo_dominant_color,
    coll.cover_photo_blurhash,
    -- POI info
    p.id,
    p.google_place_id::text,
    p.city_slug::text,
    p.name::text,
    p.name_en::text,
    p.name_fr::text,
    p.slug_en::text,
    p.slug_fr::text,
    p.primary_type::text,
    p.subcategories,
    p.address_street::text,
    p.city::text,
    p.country::text,
    p.lat::double precision,
    p.lng::double precision,
    p.opening_hours,
    p.price_level::text,
    CASE p.price_level
      WHEN 'PRICE_LEVEL_INEXPENSIVE' THEN 1
      WHEN 'PRICE_LEVEL_MODERATE' THEN 2
      WHEN 'PRICE_LEVEL_EXPENSIVE' THEN 3
      WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4
      ELSE NULL
    END::int as price_level_numeric,
    p.phone::text,
    p.website::text,
    p.district_slug::text,
    p.neighbourhood_slug::text,
    p.publishable_status::text,
    p.ai_summary::text,
    p.ai_summary_en::text,
    p.ai_summary_fr::text,
    p.tags,
    public.tags_to_text_arr_deep(p.tags) AS tags_flat,
    p.created_at,
    p.updated_at,
    -- Scores
    COALESCE(sc.sc_gatto_score, 0)::numeric AS gatto_score,
    COALESCE(sc.sc_digital_score, 0)::numeric AS digital_score,
    COALESCE(sc.sc_awards_bonus, 0)::numeric AS awards_bonus,
    COALESCE(sc.sc_freshness_bonus, 0)::numeric AS freshness_bonus,
    sc.sc_calculated_at AS calculated_at,
    -- Rating
    COALESCE(rt.rt_rating_value, 0)::numeric AS rating_value,
    COALESCE(rt.rt_reviews_count, 0)::integer AS rating_reviews_count,
    -- Mentions
    COALESCE(mt.mt_mentions_count, 0)::integer AS mentions_count,
    COALESCE(mt.mt_mentions_sample, '[]'::jsonb) AS mentions_sample,
    -- Collection item specific
    ci.position,
    ci.reason,
    -- Total count
    COUNT(*) OVER() AS total_count
  FROM coll
  INNER JOIN public.collection_item ci ON ci.collection_id = coll.id
  INNER JOIN public.poi p ON p.id = ci.poi_id
  LEFT JOIN scores sc ON sc.poi_id = p.id
  LEFT JOIN ratings rt ON rt.poi_id = p.id
  LEFT JOIN mentions mt ON mt.poi_id = p.id
  WHERE p.publishable_status = 'eligible'
  ORDER BY ci.position ASC, p.id ASC
  LIMIT v_limit
  OFFSET v_offset;
END;
$$ LANGUAGE plpgsql STABLE;


-- ==================================================
-- Indexes for optimal performance
-- ==================================================

-- Index for city_slug filtering on collections (if not exists)
CREATE INDEX IF NOT EXISTS idx_collection_city_updated
ON collection (city_slug, updated_at DESC);

-- Index for collection_item position sorting (already exists per schema)
-- CREATE INDEX IF NOT EXISTS idx_collection_item_pos
-- ON collection_item (collection_id, position);

-- ==================================================
-- Usage examples
-- ==================================================

-- Get collections for Paris
-- SELECT * FROM list_collections(
--   p_city_slug := 'paris',
--   p_limit := 20,
--   p_page := 1
-- );

-- Get POIs from a collection
-- SELECT * FROM get_collection_pois(
--   p_slug := 'adresses-cocooning-pour-l-automne',
--   p_limit := 50,
--   p_page := 1
-- );
