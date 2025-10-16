CREATE OR REPLACE FUNCTION public.rpc_get_poi_facets(
  p_city_slug           text,
  p_categories          text[] DEFAULT NULL,
  p_subcategories       text[] DEFAULT NULL,
  p_price_min           integer DEFAULT NULL,
  p_price_max           integer DEFAULT NULL,
  p_rating_min          numeric DEFAULT NULL,
  p_rating_max          numeric DEFAULT NULL,
  p_district_slugs      text[] DEFAULT NULL,
  p_neighbourhood_slugs text[] DEFAULT NULL,
  p_tags_all            text[] DEFAULT NULL,
  p_tags_any            text[] DEFAULT NULL,
  p_awarded             boolean DEFAULT NULL,
  p_fresh               boolean DEFAULT NULL,
  p_lang                text DEFAULT 'fr',
  p_awards_providers    text[] DEFAULT NULL,
  p_sort                text DEFAULT 'gatto'
)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH norm AS (
  SELECT
    lower(p_city_slug) AS city_slug,
    CASE WHEN p_categories IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_categories) x(x)) END AS categories,
    CASE WHEN p_subcategories IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_subcategories) x(x)) END AS subcats,
    CASE WHEN p_tags_all IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_all) x(x)) END AS tags_all_lc,
    CASE WHEN p_tags_any IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_any) x(x)) END AS tags_any_lc,
    CASE WHEN p_district_slugs IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_district_slugs) x(x)) END AS district_slugs,
    CASE WHEN p_neighbourhood_slugs IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_neighbourhood_slugs) x(x)) END AS neighbourhood_slugs,
    CASE WHEN p_awards_providers IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_awards_providers) x(x)) END AS awards_providers_lc,
    CASE WHEN p_lang IN ('fr','en') THEN p_lang ELSE 'fr' END AS lang,
    CASE WHEN p_price_min BETWEEN 1 AND 4 THEN p_price_min ELSE NULL END AS price_min_raw,
    CASE WHEN p_price_max BETWEEN 1 AND 4 THEN p_price_max ELSE NULL END AS price_max_raw,
    CASE WHEN p_rating_min BETWEEN 0 AND 5 THEN p_rating_min ELSE NULL END AS rating_min_raw,
    CASE WHEN p_rating_max BETWEEN 0 AND 5 THEN p_rating_max ELSE NULL END AS rating_max_raw,
    p_awarded AS awarded,
    p_fresh   AS fresh,
    p_sort    AS sort
),
norm_ranges AS (
  SELECT
    city_slug,
    categories,
    subcats,
    tags_all_lc,
    tags_any_lc,
    district_slugs,
    neighbourhood_slugs,
    awards_providers_lc,
    lang,
    awarded,
    fresh,
    sort,
    CASE
      WHEN price_min_raw IS NOT NULL AND price_max_raw IS NOT NULL AND price_min_raw > price_max_raw THEN price_max_raw
      ELSE price_min_raw
    END AS price_min,
    CASE
      WHEN price_min_raw IS NOT NULL AND price_max_raw IS NOT NULL AND price_min_raw > price_max_raw THEN price_min_raw
      ELSE price_max_raw
    END AS price_max,
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
poi_base AS (
  SELECT
    p.id,
    p.city_slug,
    lower(p.category::text) AS category_slug,
    p.category,
    p.subcategories,
    (SELECT array_agg(lower(val)) FROM unnest(p.subcategories) val) AS subcategories_lc,
    p.price_level,
    CASE p.price_level
      WHEN 'PRICE_LEVEL_INEXPENSIVE'    THEN 1
      WHEN 'PRICE_LEVEL_MODERATE'       THEN 2
      WHEN 'PRICE_LEVEL_EXPENSIVE'      THEN 3
      WHEN 'PRICE_LEVEL_VERY_EXPENSIVE' THEN 4
      ELSE NULL
    END AS price_numeric,
    lower(p.district_slug)     AS district_slug,
    p.district_name,
    lower(p.neighbourhood_slug) AS neighbourhood_slug,
    p.neighbourhood_name,
    p.tags,
    public.tags_to_text_arr_deep(p.tags) AS tags_flat,
    COALESCE((
      SELECT array_agg(DISTINCT lower(aw->>'provider'))
      FROM jsonb_array_elements(COALESCE(p.tags->'badges'->'awards','[]'::jsonb)) aw
      WHERE aw ? 'provider'
    ), '{}'::text[]) AS awards_providers
  FROM public.poi p
  WHERE p.publishable_status = 'eligible'
    AND p.city_slug = (SELECT city_slug FROM norm_ranges)
),
with_metrics AS (
  SELECT
    b.*,
    l.awards_bonus,
    l.freshness_bonus,
    COALESCE(r.rating_value::numeric, NULL) AS rating_value,
    COALESCE(r.reviews_count::int, NULL)    AS rating_reviews_count
  FROM poi_base b
  JOIN public.latest_gatto_scores l ON l.poi_id = b.id
  LEFT JOIN public.latest_google_rating r ON r.poi_id = b.id
),
filtered AS (
  SELECT w.*
  FROM with_metrics w, norm_ranges n
  WHERE
    (n.district_slugs IS NULL OR (w.district_slug IS NOT NULL AND w.district_slug = ANY(n.district_slugs)))
    AND (n.neighbourhood_slugs IS NULL OR (w.neighbourhood_slug IS NOT NULL AND w.neighbourhood_slug = ANY(n.neighbourhood_slugs)))
    AND (n.categories IS NULL OR w.category_slug = ANY(n.categories))
    AND (n.subcats IS NULL OR (w.subcategories_lc IS NOT NULL AND w.subcategories_lc && n.subcats))
    AND (n.price_min IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric >= n.price_min))
    AND (n.price_max IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric <= n.price_max))
    AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
    AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
    AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
    AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
    AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                          OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
    AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                        OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
    AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
),
tot AS (
  SELECT COUNT(*)::int AS total_results FROM filtered
),
facet_category AS (
  SELECT w.category_slug AS value, COUNT(*)::int AS count
  FROM with_metrics w, norm_ranges n
  WHERE
    (n.subcats IS NULL OR (w.subcategories_lc IS NOT NULL AND w.subcategories_lc && n.subcats))
    AND (n.price_min IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric >= n.price_min))
    AND (n.price_max IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric <= n.price_max))
    AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
    AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
    AND (n.district_slugs IS NULL OR (w.district_slug IS NOT NULL AND w.district_slug = ANY(n.district_slugs)))
    AND (n.neighbourhood_slugs IS NULL OR (w.neighbourhood_slug IS NOT NULL AND w.neighbourhood_slug = ANY(n.neighbourhood_slugs)))
    AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
    AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
    AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                          OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
    AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                        OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
    AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
  GROUP BY w.category_slug
  HAVING COUNT(*) > 0
  ORDER BY count DESC
),
facet_subcategories AS (
  SELECT val AS value, COUNT(*)::int AS count
  FROM (
    SELECT unnest(w.subcategories_lc) AS val
    FROM with_metrics w, norm_ranges n
    WHERE
      (n.categories IS NULL OR w.category_slug = ANY(n.categories))
      AND (n.price_min IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric >= n.price_min))
      AND (n.price_max IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric <= n.price_max))
      AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
      AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
      AND (n.district_slugs IS NULL OR (w.district_slug IS NOT NULL AND w.district_slug = ANY(n.district_slugs)))
      AND (n.neighbourhood_slugs IS NULL OR (w.neighbourhood_slug IS NOT NULL AND w.neighbourhood_slug = ANY(n.neighbourhood_slugs)))
      AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
      AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
      AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                            OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
      AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                          OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
      AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
      AND w.subcategories_lc IS NOT NULL
  ) s
  GROUP BY val
  HAVING COUNT(*) > 0
  ORDER BY count DESC
  LIMIT 200
),
facet_price AS (
  SELECT w.price_numeric::text AS value, COUNT(*)::int AS count
  FROM with_metrics w, norm_ranges n
  WHERE
    (n.categories IS NULL OR w.category_slug = ANY(n.categories))
    AND (n.subcats IS NULL OR (w.subcategories_lc IS NOT NULL AND w.subcategories_lc && n.subcats))
    AND (n.district_slugs IS NULL OR (w.district_slug IS NOT NULL AND w.district_slug = ANY(n.district_slugs)))
    AND (n.neighbourhood_slugs IS NULL OR (w.neighbourhood_slug IS NOT NULL AND w.neighbourhood_slug = ANY(n.neighbourhood_slugs)))
    AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
    AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
    AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                          OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
    AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                        OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
    AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
    AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
    AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
    AND w.price_numeric IS NOT NULL
  GROUP BY w.price_numeric
  ORDER BY w.price_numeric
),
facet_districts AS (
  SELECT
    w.district_slug AS value,
    w.district_name AS label,
    COUNT(*)::int   AS count
  FROM with_metrics w, norm_ranges n
  WHERE
    (n.categories IS NULL OR w.category_slug = ANY(n.categories))
    AND (n.subcats IS NULL OR (w.subcategories_lc IS NOT NULL AND w.subcategories_lc && n.subcats))
    AND (n.price_min IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric >= n.price_min))
    AND (n.price_max IS NULL OR (w.price_numeric IS NOT NULL AND w.price_numeric <= n.price_max))
    AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
    AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
    AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
    AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
    AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                          OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
    AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                        OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
    AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
    AND w.district_slug IS NOT NULL
  GROUP BY w.district_slug, w.district_name
  HAVING COUNT(*) > 0
  ORDER BY count DESC
  LIMIT 200
),
awards_flat AS (
  SELECT w.id, provider
  FROM filtered w
  CROSS JOIN LATERAL (
    SELECT lower(aw->>'provider') AS provider
    FROM jsonb_array_elements(COALESCE(w.tags->'badges'->'awards','[]'::jsonb)) aw
    WHERE aw ? 'provider'
  ) p
),
facet_awards AS (
  SELECT provider AS value,
         initcap(provider) AS label,
         COUNT(DISTINCT id)::int AS count
  FROM awards_flat
  GROUP BY provider
  HAVING COUNT(DISTINCT id) > 0
  ORDER BY count DESC
),
price_levels_meta AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'value', lvl::text,
        'label',
          CASE lvl
            WHEN 1 THEN '€'
            WHEN 2 THEN '€€'
            WHEN 3 THEN '€€€'
            WHEN 4 THEN '€€€€'
            ELSE lvl::text
          END
      )
      ORDER BY lvl
    ),
    '[]'::jsonb
  ) AS levels
  FROM (
    SELECT DISTINCT w.price_numeric AS lvl
    FROM with_metrics w, norm_ranges n
    WHERE
      (n.categories IS NULL OR w.category_slug = ANY(n.categories))
      AND (n.subcats IS NULL OR (w.subcategories_lc IS NOT NULL AND w.subcategories_lc && n.subcats))
      AND (n.district_slugs IS NULL OR (w.district_slug IS NOT NULL AND w.district_slug = ANY(n.district_slugs)))
      AND (n.neighbourhood_slugs IS NULL OR (w.neighbourhood_slug IS NOT NULL AND w.neighbourhood_slug = ANY(n.neighbourhood_slugs)))
      AND (n.tags_all_lc IS NULL OR w.tags_flat @> n.tags_all_lc)
      AND (n.tags_any_lc IS NULL OR w.tags_flat && n.tags_any_lc)
      AND (n.awarded IS NULL OR (n.awarded = TRUE  AND COALESCE(w.awards_bonus,0) > 0)
                            OR (n.awarded = FALSE AND COALESCE(w.awards_bonus,0) = 0))
      AND (n.fresh IS NULL OR (n.fresh = TRUE  AND COALESCE(w.freshness_bonus,0) > 0)
                          OR (n.fresh = FALSE AND COALESCE(w.freshness_bonus,0) = 0))
      AND (n.awards_providers_lc IS NULL OR (w.awards_providers && n.awards_providers_lc))
      AND (n.rating_min IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value >= n.rating_min))
      AND (n.rating_max IS NULL OR (w.rating_value IS NOT NULL AND w.rating_value <= n.rating_max))
      AND w.price_numeric IS NOT NULL
  ) q
),
rating_meta AS (
  SELECT
    COALESCE(MIN(w.rating_value), 0)::numeric(3,2) AS min_rating,
    COALESCE(MAX(w.rating_value), 0)::numeric(3,2) AS max_rating
  FROM filtered w
)
SELECT jsonb_build_object(
  'context', jsonb_build_object(
    'city', (SELECT city_slug FROM norm_ranges),
    'total_results', (SELECT total_results FROM tot),
    'applied_filters', jsonb_strip_nulls(jsonb_build_object(
      'category',       (SELECT categories FROM norm_ranges),
      'subcategory',    (SELECT subcats FROM norm_ranges),
      'price',          (SELECT CASE WHEN price_min IS NULL AND price_max IS NULL THEN NULL
                                     ELSE jsonb_build_object('min', price_min, 'max', price_max) END FROM norm_ranges),
      'rating',         (SELECT CASE WHEN rating_min IS NULL AND rating_max IS NULL THEN NULL
                                     ELSE jsonb_build_object('min', rating_min, 'max', rating_max) END FROM norm_ranges),
      'district_slug',  (SELECT district_slugs FROM norm_ranges),
      'neighbourhood_slug', (SELECT neighbourhood_slugs FROM norm_ranges),
      'awards_providers', (SELECT awards_providers_lc FROM norm_ranges),
      'tags_all',       (SELECT tags_all_lc FROM norm_ranges),
      'tags_any',       (SELECT tags_any_lc FROM norm_ranges),
      'awarded',        (SELECT awarded FROM norm_ranges),
      'fresh',          (SELECT fresh FROM norm_ranges),
      'sort',           (SELECT sort FROM norm_ranges)
    ))
  ),
  'facets', jsonb_build_object(
    'category',      COALESCE( (SELECT jsonb_agg(jsonb_build_object('value', value, 'label', initcap(value), 'count', count)) FROM facet_category), '[]'::jsonb ),
    'subcategories', COALESCE( (SELECT jsonb_agg(jsonb_build_object('value', value, 'label', initcap(replace(value,'_',' ')), 'count', count)) FROM facet_subcategories), '[]'::jsonb ),
    'price',         COALESCE( (SELECT jsonb_agg(jsonb_build_object('value', value, 'label',
                              CASE value WHEN '1' THEN '€' WHEN '2' THEN '€€' WHEN '3' THEN '€€€' WHEN '4' THEN '€€€€' ELSE value END,
                              'count', count)) FROM facet_price), '[]'::jsonb ),
    'price_levels',  (SELECT levels FROM price_levels_meta),
    'districts',     COALESCE( (SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_districts), '[]'::jsonb ),
    'awards',        COALESCE( (SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_awards), '[]'::jsonb ),
    'rating_range',  jsonb_build_object(
                       'min', (SELECT min_rating FROM rating_meta),
                       'max', (SELECT max_rating FROM rating_meta)
                     )
  )
);
$$;
