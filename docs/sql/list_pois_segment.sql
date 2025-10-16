CREATE OR REPLACE FUNCTION public.list_pois_segment(
  p_city_slug           text,
  p_category            text DEFAULT NULL,
  p_categories          text[] DEFAULT NULL,
  p_subcategories       text[] DEFAULT NULL,
  p_price_level         text DEFAULT NULL,
  p_price_min           integer DEFAULT NULL,
  p_price_max           integer DEFAULT NULL,
  p_neighbourhood       text DEFAULT NULL,
  p_neighbourhood_slugs text[] DEFAULT NULL,
  p_district            text DEFAULT NULL,
  p_district_slugs      text[] DEFAULT NULL,
  p_tags_all            text[] DEFAULT NULL,
  p_tags_any            text[] DEFAULT NULL,
  p_awarded             boolean DEFAULT NULL,
  p_fresh               boolean DEFAULT NULL,
  p_sort                text DEFAULT 'gatto',
  p_segment             text DEFAULT 'gatto',
  p_limit               integer DEFAULT 24,
  p_after_score         numeric DEFAULT NULL,
  p_after_id            uuid DEFAULT NULL,
  p_awards_providers    text[] DEFAULT NULL,
  p_rating_min          numeric DEFAULT NULL,
  p_rating_max          numeric DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  google_place_id text,
  city_slug text,
  name text,
  name_en text,
  name_fr text,
  slug_en text,
  slug_fr text,
  category text,
  address_street text,
  city text,
  country text,
  lat double precision,
  lng double precision,
  opening_hours jsonb,
  price_level text,
  phone text,
  website text,
  district_slug text,
  neighbourhood_slug text,
  publishable_status text,
  ai_summary text,
  ai_summary_en text,
  ai_summary_fr text,
  tags jsonb,
  tags_flat text[],
  subcategories text[],
  price_level_numeric integer,
  created_at timestamptz,
  updated_at timestamptz,
  gatto_score numeric,
  digital_score numeric,
  awards_bonus numeric,
  freshness_bonus numeric,
  mentions_count integer,
  rating_value numeric,
  rating_reviews_count integer,
  calculated_at timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  WITH norm AS (
    SELECT
      CASE WHEN p_tags_all IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_tags_all) AS t(x)) END AS all_lc,
      CASE WHEN p_tags_any IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_tags_any) AS t(x)) END AS any_lc,
      CASE WHEN p_categories IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_categories) AS t(x)) END AS categories_lc,
      CASE WHEN p_subcategories IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_subcategories) AS t(x)) END AS subcategories_lc,
      CASE WHEN p_district_slugs IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_district_slugs) AS t(x)) END AS district_slugs_lc,
      CASE WHEN p_neighbourhood_slugs IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(x)) FROM unnest(p_neighbourhood_slugs) AS t(x)) END AS neighbourhood_slugs_lc,
      CASE WHEN p_awards_providers IS NULL THEN NULL
           ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_awards_providers) AS t(x)) END AS awards_providers_lc,
      CASE WHEN p_price_min BETWEEN 1 AND 4 THEN p_price_min ELSE NULL END AS price_min_raw,
      CASE WHEN p_price_max BETWEEN 1 AND 4 THEN p_price_max ELSE NULL END AS price_max_raw,
      CASE WHEN p_rating_min BETWEEN 0 AND 5 THEN p_rating_min ELSE NULL END AS rating_min_raw,
      CASE WHEN p_rating_max BETWEEN 0 AND 5 THEN p_rating_max ELSE NULL END AS rating_max_raw,
      CASE p_price_level
        WHEN 'PRICE_LEVEL_INEXPENSIVE'    THEN 1
        WHEN 'PRICE_LEVEL_MODERATE'       THEN 2
        WHEN 'PRICE_LEVEL_EXPENSIVE'      THEN 3
        WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4
        ELSE NULL
      END AS legacy_price_level
  ),
  norm_ranges AS (
    SELECT
      all_lc,
      any_lc,
      categories_lc,
      subcategories_lc,
      district_slugs_lc,
      neighbourhood_slugs_lc,
      awards_providers_lc,
      legacy_price_level,
      CASE
        WHEN price_min_raw IS NOT NULL AND price_max_raw IS NOT NULL AND price_min_raw > price_max_raw THEN price_max_raw
        ELSE price_min_raw
      END AS price_min_tmp,
      CASE
        WHEN price_min_raw IS NOT NULL AND price_max_raw IS NOT NULL AND price_min_raw > price_max_raw THEN price_min_raw
        ELSE price_max_raw
      END AS price_max_tmp,
      CASE
        WHEN rating_min_raw IS NOT NULL AND rating_max_raw IS NOT NULL AND rating_min_raw > rating_max_raw THEN rating_max_raw
        ELSE rating_min_raw
      END AS rating_min,
      CASE
        WHEN rating_min_raw IS NOT NULL AND rating_max_raw IS NOT NULL AND rating_min_raw > rating_max_raw THEN rating_min_raw
        ELSE rating_max_raw
      END AS rating_max
    FROM norm
  ),
  norm_final AS (
    SELECT
      all_lc,
      any_lc,
      categories_lc,
      subcategories_lc,
      district_slugs_lc,
      neighbourhood_slugs_lc,
      awards_providers_lc,
      COALESCE(price_min_tmp, legacy_price_level) AS price_min,
      COALESCE(price_max_tmp, legacy_price_level) AS price_max,
      rating_min,
      rating_max
    FROM norm_ranges
  ),
  base AS (
    SELECT
      f.*,
      lower(f.category::text) AS category_slug,
      (SELECT array_agg(lower(val)) FROM unnest(f.subcategories) val) AS subcategories_lc,
      public.tags_to_text_arr_deep(f.tags) AS tags_flat,
      COALESCE((
        SELECT array_agg(DISTINCT lower(aw->>'provider'))
        FROM jsonb_array_elements(COALESCE(f.tags->'badges'->'awards','[]'::jsonb)) aw
        WHERE aw ? 'provider'
      ), '{}'::text[]) AS awards_providers,
      CASE f.price_level
        WHEN 'PRICE_LEVEL_INEXPENSIVE'    THEN 1
        WHEN 'PRICE_LEVEL_MODERATE'       THEN 2
        WHEN 'PRICE_LEVEL_EXPENSIVE'      THEN 3
        WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4
        ELSE NULL
      END AS price_level_numeric,
      lower(f.district_slug) AS district_slug_lc,
      lower(f.neighbourhood_slug) AS neighbourhood_slug_lc
    FROM public.poi f
  ),
  filtered AS (
    SELECT
      b.id, b.google_place_id, b.city_slug, b.name, b.name_en, b.name_fr,
      b.slug_en, b.slug_fr, b.category::text AS category,
      b.address_street, b.city, b.country,
      b.lat::double precision AS lat, b.lng::double precision AS lng,
      b.opening_hours, b.price_level::text AS price_level, b.phone, b.website,
      b.district_slug, b.neighbourhood_slug,
      b.publishable_status::text AS publishable_status,
      b.ai_summary, b.ai_summary_en, b.ai_summary_fr,
      b.tags, b.subcategories,
      b.created_at, b.updated_at,
      b.tags_flat,
      b.subcategories_lc,
      b.awards_providers,
      b.price_level_numeric
    FROM base b
    CROSS JOIN norm_final n
    WHERE b.publishable_status = 'eligible'
      AND b.city_slug = COALESCE(p_city_slug, b.city_slug)
      AND (
        (n.categories_lc IS NULL AND (p_category IS NULL OR b.category_slug = lower(p_category)))
        OR
        (n.categories_lc IS NOT NULL AND b.category_slug = ANY(n.categories_lc))
      )
      AND (n.subcategories_lc IS NULL OR (b.subcategories_lc IS NOT NULL AND b.subcategories_lc && n.subcategories_lc))
      AND (n.price_min IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
      AND (n.price_max IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
      AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
      AND (n.district_slugs_lc IS NULL OR (b.district_slug IS NOT NULL AND b.district_slug_lc = ANY(n.district_slugs_lc)))
      AND (p_neighbourhood IS NULL OR b.neighbourhood_slug ILIKE '%'||p_neighbourhood||'%')
      AND (p_district IS NULL OR b.district_slug ILIKE '%'||p_district||'%')
      AND (n.all_lc IS NULL OR b.tags_flat @> n.all_lc)
      AND (n.any_lc IS NULL OR b.tags_flat && n.any_lc)
      AND (n.awards_providers_lc IS NULL OR (b.awards_providers && n.awards_providers_lc))
  ),
  joined AS (
    SELECT f.*,
           l.gatto_score,
           l.digital_score,
           l.awards_bonus,
           l.freshness_bonus,
           l.calculated_at,
           COALESCE(m.mentions_count, 0)::int AS mentions_count,
           COALESCE(r.rating_value::numeric, 0)::numeric AS rating_value,
           COALESCE(r.reviews_count::int, 0) AS rating_reviews_count,
           COALESCE(f.price_level_numeric, 0) AS price_level_numeric_sort
    FROM filtered f
    JOIN public.latest_gatto_scores l ON l.poi_id = f.id
    LEFT JOIN (
      SELECT poi_id, COUNT(DISTINCT domain) AS mentions_count
      FROM public.ai_mention
      WHERE ai_decision = 'ACCEPT'
      GROUP BY poi_id
    ) m ON m.poi_id = f.id
    LEFT JOIN public.latest_google_rating r ON r.poi_id = f.id
    WHERE
      (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(l.awards_bonus,0) > 0)
                        OR (p_awarded = FALSE AND COALESCE(l.awards_bonus,0) = 0))
      AND
      (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(l.freshness_bonus,0) > 0)
                        OR (p_fresh   = FALSE AND COALESCE(l.freshness_bonus,0) = 0))
      AND (p_rating_min IS NULL OR COALESCE(r.rating_value, 0) >= p_rating_min)
      AND (p_rating_max IS NULL OR COALESCE(r.rating_value, 0) <= p_rating_max)
  ),
  sorted AS (
    SELECT j.*,
           COALESCE(j.mentions_count, 0) AS mentions_count_sort
    FROM joined j
    ORDER BY
      CASE
        WHEN p_sort = 'price_desc'        THEN  j.price_level_numeric_sort
        WHEN p_sort = 'price_asc'         THEN -j.price_level_numeric_sort
        WHEN p_sort = 'mentions'          THEN  COALESCE(j.mentions_count, 0)
        WHEN p_sort = 'rating'            THEN  j.rating_value
        WHEN LOWER(p_segment) = 'digital' THEN  j.digital_score
        WHEN LOWER(p_segment) = 'awarded' THEN  j.awards_bonus
        WHEN LOWER(p_segment) = 'fresh'   THEN  j.freshness_bonus
        ELSE                                  j.gatto_score
      END DESC NULLS LAST,
      j.gatto_score   DESC NULLS LAST,
      j.calculated_at DESC NULLS LAST,
      j.id            ASC
  )
  SELECT
    s.id,
    s.google_place_id::text,
    s.city_slug::text,
    s.name::text,
    s.name_en::text,
    s.name_fr::text,
    s.slug_en::text,
    s.slug_fr::text,
    s.category::text,
    s.address_street::text,
    s.city::text,
    s.country::text,
    s.lat,
    s.lng,
    s.opening_hours,
    s.price_level::text,
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
    s.subcategories,
    s.price_level_numeric,
    s.created_at,
    s.updated_at,
    s.gatto_score,
    s.digital_score,
    s.awards_bonus,
    s.freshness_bonus,
    s.mentions_count,
    s.rating_value,
    s.rating_reviews_count,
    s.calculated_at
  FROM sorted s
  WHERE
    p_after_score IS NULL
    OR (
      (CASE
         WHEN p_sort = 'price_desc'        THEN ( s.price_level_numeric_sort, s.id )
         WHEN p_sort = 'price_asc'         THEN ( -s.price_level_numeric_sort, s.id )
         WHEN p_sort = 'mentions'          THEN ( s.mentions_count_sort, s.id )
         WHEN p_sort = 'rating'            THEN ( s.rating_value, s.id )
         WHEN LOWER(p_segment) = 'digital' THEN ( s.digital_score, s.id )
         WHEN LOWER(p_segment) = 'awarded' THEN ( s.awards_bonus, s.id )
         WHEN LOWER(p_segment) = 'fresh'   THEN ( s.freshness_bonus, s.id )
         ELSE                                  ( s.gatto_score, s.id )
       END) < (p_after_score, p_after_id)
    )
  LIMIT p_limit;
END;
$$;
