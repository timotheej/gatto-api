-- =====================================================
-- rpc_get_pois_facets - Facettes contextuelles pour les POI
-- =====================================================
-- Version avec support hiérarchique (parent_category + type_key)
-- et traductions multilingues via poi_types
--
-- DEPLOY: Exécuter ce script dans Supabase SQL Editor
--

CREATE OR REPLACE FUNCTION public.rpc_get_pois_facets(
  p_city_slug text DEFAULT NULL,
  p_parent_categories text[] DEFAULT NULL,  -- Nouveau: filtrer par groupes (ex: ['restaurant', 'bar'])
  p_type_keys text[] DEFAULT NULL,          -- Nouveau: filtrer par types spécifiques (ex: ['italian_restaurant'])
  p_district_slugs text[] DEFAULT NULL,
  p_neighbourhood_slugs text[] DEFAULT NULL,
  p_tags_all text[] DEFAULT NULL,
  p_tags_any text[] DEFAULT NULL,
  p_awards_providers text[] DEFAULT NULL,
  p_price_min int DEFAULT NULL,
  p_price_max int DEFAULT NULL,
  p_rating_min numeric DEFAULT NULL,
  p_rating_max numeric DEFAULT NULL,
  p_bbox numeric[] DEFAULT NULL,
  p_awarded boolean DEFAULT NULL,
  p_fresh boolean DEFAULT NULL,
  p_sort text DEFAULT 'gatto',
  p_lang text DEFAULT 'fr'                  -- Nouveau: langue pour les labels (fr|en)
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_lang text := COALESCE(lower(p_lang), 'fr');
BEGIN
  RETURN (
    WITH
    /* -----------------------------
       1) Normalisation des paramètres
       ----------------------------- */
    norm AS (
      SELECT
        lower(p_city_slug) AS city_slug,
        v_lang AS lang,
        CASE WHEN p_parent_categories   IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_parent_categories)   AS t(x)) END AS parent_categories_lc,
        CASE WHEN p_type_keys           IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_type_keys)           AS t(x)) END AS type_keys_lc,
        CASE WHEN p_district_slugs      IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_district_slugs)      AS t(x)) END AS district_slugs_lc,
        CASE WHEN p_neighbourhood_slugs IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_neighbourhood_slugs) AS t(x)) END AS neighbourhood_slugs_lc,
        CASE WHEN p_tags_all            IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_all)            AS t(x)) END AS tags_all_lc,
        CASE WHEN p_tags_any            IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_tags_any)            AS t(x)) END AS tags_any_lc,
        CASE WHEN p_awards_providers    IS NULL THEN NULL ELSE (SELECT array_agg(lower(trim(x))) FROM unnest(p_awards_providers)    AS t(x)) END AS awards_providers_lc,
        CASE WHEN p_price_min BETWEEN 1 AND 4 THEN p_price_min ELSE NULL END AS price_min,
        CASE WHEN p_price_max BETWEEN 1 AND 4 THEN p_price_max ELSE NULL END AS price_max,
        CASE WHEN p_rating_min BETWEEN 0 AND 5 THEN p_rating_min ELSE NULL END AS rating_min,
        CASE WHEN p_rating_max BETWEEN 0 AND 5 THEN p_rating_max ELSE NULL END AS rating_max,
        CASE
          WHEN p_bbox IS NOT NULL AND array_length(p_bbox,1)=4
           AND p_bbox[1] BETWEEN -90 AND 90    -- lat_min
           AND p_bbox[3] BETWEEN -90 AND 90    -- lat_max
           AND p_bbox[2] BETWEEN -180 AND 180  -- lng_min
           AND p_bbox[4] BETWEEN -180 AND 180  -- lng_max
           AND p_bbox[1] < p_bbox[3]
           AND p_bbox[2] < p_bbox[4]
          THEN p_bbox
          ELSE NULL
        END AS bbox_valid
    ),

    /* -----------------------------
       1b) Expansion des filtres via poi_types
           Si parent_categories fourni, on récupère tous les type_keys associés
       ----------------------------- */
    expanded_types AS (
      SELECT DISTINCT
        pt.type_key,
        pt.parent_category
      FROM public.poi_types pt
      CROSS JOIN norm n
      WHERE pt.is_active = true
        AND (
          -- Si parent_categories fourni, inclure tous les types de ces groupes
          (n.parent_categories_lc IS NOT NULL AND lower(pt.parent_category) = ANY(n.parent_categories_lc))
          -- Si type_keys fourni, inclure ces types spécifiques
          OR (n.type_keys_lc IS NOT NULL AND lower(pt.type_key) = ANY(n.type_keys_lc))
          -- Si aucun filtre de type, inclure tous (pour facettes)
          OR (n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL)
        )
    ),

    /* -----------------------------
       2) Tables métriques (perf)
       ----------------------------- */
    scores AS (
      SELECT poi_id,
             gatto_score     AS sc_gatto_score,
             digital_score   AS sc_digital_score,
             awards_bonus    AS sc_awards_bonus,
             freshness_bonus AS sc_freshness_bonus,
             calculated_at   AS sc_calculated_at
      FROM public.latest_gatto_scores
    ),
    ratings AS (
      SELECT poi_id,
             rating_value  AS rt_rating_value,
             reviews_count AS rt_reviews_count
      FROM public.latest_google_rating
    ),
    mentions AS (
      SELECT am.poi_id, COUNT(DISTINCT am.domain)::int AS mt_mentions_count
      FROM public.ai_mention am
      WHERE am.ai_decision = 'ACCEPT'
      GROUP BY am.poi_id
    ),

    /* -----------------------------
       3) Base enrichie
       ----------------------------- */
    base AS (
      SELECT
        p.id,
        lower(p.city_slug) AS city_slug,
        p.primary_type,
        p.subcategories,
        p.price_level,
        p.lat, p.lng,
        p.district_slug, p.district_name,
        p.neighbourhood_slug, p.neighbourhood_name,
        p.tags,
        p.publishable_status,

        /* champs calculés pour filtres */
        lower(p.primary_type::text) AS primary_type_slug,
        (SELECT array_agg(lower(val)) FROM unnest(p.subcategories) AS u(val)) AS subcategories_lc,
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

        /* awards providers extraits de la colonne awards */
        COALESCE((
          SELECT array_agg(DISTINCT lower(aw->>'provider'))
          FROM jsonb_array_elements(COALESCE(p.awards,'[]'::jsonb)) aw
          WHERE aw ? 'provider'
        ), '{}'::text[]) AS awards_providers,

        /* Calcul de relevance_score et type matching */
        CASE
          -- Match exact sur primary_type = type_key recherché
          WHEN EXISTS (
            SELECT 1 FROM expanded_types et
            WHERE lower(et.type_key) = lower(p.primary_type::text)
          ) THEN 1.0
          -- Match dans subcategories = type_key recherché
          WHEN EXISTS (
            SELECT 1 FROM expanded_types et, unnest(p.subcategories) AS sub
            WHERE lower(et.type_key) = lower(sub)
          ) THEN 0.5
          ELSE 0.0
        END::numeric AS type_relevance_score,

        /* métriques jointes */
        sc.sc_gatto_score     AS gatto_score,
        sc.sc_digital_score   AS digital_score,
        sc.sc_awards_bonus    AS awards_bonus,
        sc.sc_freshness_bonus AS freshness_bonus,
        sc.sc_calculated_at   AS calculated_at,
        COALESCE(rt.rt_rating_value, 0)::numeric AS rating_value,
        COALESCE(rt.rt_reviews_count, 0)         AS rating_reviews_count,
        COALESCE(mt.mt_mentions_count, 0)::int   AS mentions_count
      FROM public.poi p
      JOIN scores  sc ON sc.poi_id = p.id
      LEFT JOIN ratings  rt ON rt.poi_id = p.id
      LEFT JOIN mentions mt ON mt.poi_id = p.id
      WHERE p.publishable_status = 'eligible'
    ),

    /* -----------------------------------------
       4) Filtres "tous appliqués" (GLOBAL/BBOX)
       ----------------------------------------- */
    filtered_global AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE b.city_slug = n.city_slug
        -- Nouveau: filtrage par types (parent_categories OU type_keys) via type_relevance_score
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    filtered_bbox AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE n.bbox_valid IS NOT NULL
        AND b.city_slug = n.city_slug
        AND b.lat IS NOT NULL AND b.lng IS NOT NULL
        AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
        AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
        -- Nouveau: filtrage par types (parent_categories OU type_keys) via type_relevance_score
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),

    /* ----------------------------------------------------------------
       5) PIVOT — Exclure la dimension lors du calcul des facettes
          (seulement pour: primary_type, district_slug, neighbourhood_slug, awards)
       ---------------------------------------------------------------- */
    excl_primary_type_global AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE b.city_slug = n.city_slug
        -- EXCLUS: filtre de types (parent_categories / type_keys)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_district_global AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE b.city_slug = n.city_slug
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        -- EXCLUS: district_slugs_lc
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_neighbourhood_global AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE b.city_slug = n.city_slug
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug IS NOT NULL AND b.district_slug_lc = ANY(n.district_slugs_lc)))
        -- EXCLUS: neighbourhood_slugs_lc
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_awards_global AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE b.city_slug = n.city_slug
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        -- EXCLUS: awards_providers_lc
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),

    -- BBOX pivots
    excl_primary_type_bbox AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE n.bbox_valid IS NOT NULL
        AND b.city_slug = n.city_slug
        AND b.lat IS NOT NULL AND b.lng IS NOT NULL
        AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
        AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
        -- EXCLUS: filtre de types (parent_categories / type_keys)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_district_bbox AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE n.bbox_valid IS NOT NULL
        AND b.city_slug = n.city_slug
        AND b.lat IS NOT NULL AND b.lng IS NOT NULL
        AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
        AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        -- EXCLUS: district_slugs_lc
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_neighbourhood_bbox AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE n.bbox_valid IS NOT NULL
        AND b.city_slug = n.city_slug
        AND b.lat IS NOT NULL AND b.lng IS NOT NULL
        AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
        AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug IS NOT NULL AND b.district_slug_lc = ANY(n.district_slugs_lc)))
        -- EXCLUS: neighbourhood_slugs_lc
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        AND (n.awards_providers_lc    IS NULL OR (b.awards_providers && n.awards_providers_lc))
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),
    excl_awards_bbox AS (
      SELECT b.*
      FROM base b
      CROSS JOIN norm n
      WHERE n.bbox_valid IS NOT NULL
        AND b.city_slug = n.city_slug
        AND b.lat IS NOT NULL AND b.lng IS NOT NULL
        AND b.lat BETWEEN n.bbox_valid[1] AND n.bbox_valid[3]
        AND b.lng BETWEEN n.bbox_valid[2] AND n.bbox_valid[4]
        AND ((n.parent_categories_lc IS NULL AND n.type_keys_lc IS NULL) OR b.type_relevance_score > 0)
        AND (n.price_min              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric >= n.price_min))
        AND (n.price_max              IS NULL OR (b.price_level_numeric IS NOT NULL AND b.price_level_numeric <= n.price_max))
        AND (n.rating_min             IS NULL OR b.rating_value >= n.rating_min)
        AND (n.rating_max             IS NULL OR b.rating_value <= n.rating_max)
        AND (n.district_slugs_lc      IS NULL OR (b.district_slug     IS NOT NULL AND b.district_slug_lc      = ANY(n.district_slugs_lc)))
        AND (n.neighbourhood_slugs_lc IS NULL OR (b.neighbourhood_slug IS NOT NULL AND b.neighbourhood_slug_lc = ANY(n.neighbourhood_slugs_lc)))
        AND (n.tags_all_lc            IS NULL OR b.tags_flat @> n.tags_all_lc)
        AND (n.tags_any_lc            IS NULL OR b.tags_flat && n.tags_any_lc)
        -- EXCLUS: awards_providers_lc
        AND (p_awarded IS NULL OR (p_awarded = TRUE  AND COALESCE(b.awards_bonus,0) > 0)
                              OR  (p_awarded = FALSE AND COALESCE(b.awards_bonus,0) = 0))
        AND (p_fresh   IS NULL OR (p_fresh   = TRUE  AND COALESCE(b.freshness_bonus,0) > 0)
                              OR  (p_fresh   = FALSE AND COALESCE(b.freshness_bonus,0) = 0))
    ),

    /* -----------------------------
       6) Totaux
       ----------------------------- */
    totals AS (
      SELECT
        (SELECT COUNT(*)::int FROM filtered_global) AS total_global,
        (SELECT COUNT(*)::int FROM filtered_bbox)   AS total_bbox
    ),

    /* -----------------------------
       7) Facettes (GLOBAL) - Hiérarchiques avec traductions
       ----------------------------- */
    -- Facettes par parent_category (groupes)
    facet_global_parent_categories AS (
      SELECT
        pt.parent_category AS value,
        CASE pt.parent_category
          WHEN 'restaurant' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Restaurant' ELSE 'Restaurant' END
          WHEN 'bar' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Bar' ELSE 'Bar' END
          WHEN 'cafe' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Café' ELSE 'Café' END
          WHEN 'bakery' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Bakery' ELSE 'Boulangerie' END
          WHEN 'dessert' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Dessert' ELSE 'Dessert' END
          WHEN 'food_retail' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Food Shop' ELSE 'Épicerie' END
          WHEN 'nightlife' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Nightlife' ELSE 'Vie nocturne' END
          WHEN 'lodging' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Lodging' ELSE 'Hébergement' END
          WHEN 'culture' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Culture' ELSE 'Culture' END
          WHEN 'entertainment' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Entertainment' ELSE 'Divertissement' END
          WHEN 'wellness' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Wellness' ELSE 'Bien-être' END
          WHEN 'health' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Health' ELSE 'Santé' END
          WHEN 'sports' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Sports' ELSE 'Sports' END
          WHEN 'retail' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Shopping' ELSE 'Commerce' END
          WHEN 'services' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Services' ELSE 'Services' END
          WHEN 'automotive' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Automotive' ELSE 'Automobile' END
          WHEN 'transport' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Transportation' ELSE 'Transport' END
          WHEN 'parks' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Parks' ELSE 'Parcs' END
          WHEN 'government' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Government' ELSE 'Administration' END
          WHEN 'education' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Education' ELSE 'Éducation' END
          WHEN 'finance' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Finance' ELSE 'Finance' END
          WHEN 'other' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Other' ELSE 'Autre' END
          ELSE pt.parent_category
        END AS label,
        COUNT(DISTINCT b.id)::int AS count
      FROM excl_primary_type_global b
      JOIN public.poi_types pt ON (
        lower(pt.type_key) = lower(b.primary_type::text)
        AND pt.is_active = true
      )
      GROUP BY pt.parent_category
      ORDER BY count DESC
    ),
    -- Facettes par type_key (types spécifiques)
    facet_global_type_keys AS (
      SELECT
        pt.type_key AS value,
        CASE
          -- Si type générique (type_key = parent_category), ajouter suffix "(autre)"
          WHEN pt.type_key = pt.parent_category THEN
            CASE
              WHEN (SELECT lang FROM norm) = 'en' THEN pt.label_en || ' (other)'
              ELSE pt.label_fr || ' (autre)'
            END
          -- Sinon, label normal
          ELSE
            CASE
              WHEN (SELECT lang FROM norm) = 'en' THEN pt.label_en
              ELSE pt.label_fr
            END
        END AS label,
        pt.parent_category AS parent_category,
        COUNT(DISTINCT b.id)::int AS count
      FROM excl_primary_type_global b
      JOIN public.poi_types pt ON (
        lower(pt.type_key) = lower(b.primary_type::text)
        AND pt.is_active = true
      )
      GROUP BY pt.type_key, pt.label_en, pt.label_fr, pt.parent_category
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_global_price AS (
      SELECT price_level_numeric::text AS value, COUNT(*)::int AS count
      FROM filtered_global
      WHERE price_level_numeric IS NOT NULL
      GROUP BY price_level_numeric
      ORDER BY price_level_numeric
    ),
    facet_global_districts AS (
      SELECT district_slug AS value, MAX(district_name) AS label, COUNT(*)::int AS count
      FROM excl_district_global
      WHERE district_slug IS NOT NULL
      GROUP BY district_slug
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_global_neighbourhoods AS (
      SELECT neighbourhood_slug AS value, MAX(neighbourhood_name) AS label, COUNT(*)::int AS count
      FROM excl_neighbourhood_global
      WHERE neighbourhood_slug IS NOT NULL
      GROUP BY neighbourhood_slug
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_global_tags AS (
      SELECT t.tag AS value,
             initcap(replace(t.tag,'_',' ')) AS label,
             COUNT(*)::int AS count
      FROM (
        SELECT unnest(tags_flat) AS tag
        FROM filtered_global
        WHERE tags_flat IS NOT NULL
      ) t
      GROUP BY t.tag
      ORDER BY count DESC
      LIMIT 300
    ),
    facet_global_awards AS (
      SELECT provider AS value,
             initcap(provider) AS label,
             COUNT(DISTINCT id)::int AS count
      FROM (
        SELECT id, unnest(awards_providers) AS provider
        FROM excl_awards_global
        WHERE awards_providers IS NOT NULL AND cardinality(awards_providers) > 0
      ) awards_flat
      GROUP BY provider
      ORDER BY count DESC
    ),
    facet_global_awarded AS (
      SELECT (awards_bonus > 0) AS value, COUNT(*)::int AS count
      FROM filtered_global
      GROUP BY (awards_bonus > 0)
    ),

    /* -----------------------------
       8) Facettes (BBOX si fourni) - Hiérarchiques avec traductions
       ----------------------------- */
    -- Facettes par parent_category (groupes)
    facet_bbox_parent_categories AS (
      SELECT
        pt.parent_category AS value,
        CASE pt.parent_category
          WHEN 'restaurant' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Restaurant' ELSE 'Restaurant' END
          WHEN 'bar' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Bar' ELSE 'Bar' END
          WHEN 'cafe' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Café' ELSE 'Café' END
          WHEN 'bakery' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Bakery' ELSE 'Boulangerie' END
          WHEN 'dessert' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Dessert' ELSE 'Dessert' END
          WHEN 'food_retail' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Food Shop' ELSE 'Épicerie' END
          WHEN 'nightlife' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Nightlife' ELSE 'Vie nocturne' END
          WHEN 'lodging' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Lodging' ELSE 'Hébergement' END
          WHEN 'culture' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Culture' ELSE 'Culture' END
          WHEN 'entertainment' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Entertainment' ELSE 'Divertissement' END
          WHEN 'wellness' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Wellness' ELSE 'Bien-être' END
          WHEN 'health' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Health' ELSE 'Santé' END
          WHEN 'sports' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Sports' ELSE 'Sports' END
          WHEN 'retail' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Shopping' ELSE 'Commerce' END
          WHEN 'services' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Services' ELSE 'Services' END
          WHEN 'automotive' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Automotive' ELSE 'Automobile' END
          WHEN 'transport' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Transportation' ELSE 'Transport' END
          WHEN 'parks' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Parks' ELSE 'Parcs' END
          WHEN 'government' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Government' ELSE 'Administration' END
          WHEN 'education' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Education' ELSE 'Éducation' END
          WHEN 'finance' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Finance' ELSE 'Finance' END
          WHEN 'other' THEN CASE WHEN (SELECT lang FROM norm) = 'en' THEN 'Other' ELSE 'Autre' END
          ELSE pt.parent_category
        END AS label,
        COUNT(DISTINCT b.id)::int AS count
      FROM excl_primary_type_bbox b
      JOIN public.poi_types pt ON (
        lower(pt.type_key) = lower(b.primary_type::text)
        AND pt.is_active = true
      )
      GROUP BY pt.parent_category
      ORDER BY count DESC
    ),
    -- Facettes par type_key (types spécifiques)
    facet_bbox_type_keys AS (
      SELECT
        pt.type_key AS value,
        CASE
          -- Si type générique (type_key = parent_category), ajouter suffix "(autre)"
          WHEN pt.type_key = pt.parent_category THEN
            CASE
              WHEN (SELECT lang FROM norm) = 'en' THEN pt.label_en || ' (other)'
              ELSE pt.label_fr || ' (autre)'
            END
          -- Sinon, label normal
          ELSE
            CASE
              WHEN (SELECT lang FROM norm) = 'en' THEN pt.label_en
              ELSE pt.label_fr
            END
        END AS label,
        pt.parent_category AS parent_category,
        COUNT(DISTINCT b.id)::int AS count
      FROM excl_primary_type_bbox b
      JOIN public.poi_types pt ON (
        lower(pt.type_key) = lower(b.primary_type::text)
        AND pt.is_active = true
      )
      GROUP BY pt.type_key, pt.label_en, pt.label_fr, pt.parent_category
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_bbox_price AS (
      SELECT price_level_numeric::text AS value, COUNT(*)::int AS count
      FROM filtered_bbox
      WHERE price_level_numeric IS NOT NULL
      GROUP BY price_level_numeric
      ORDER BY price_level_numeric
    ),
    facet_bbox_districts AS (
      SELECT district_slug AS value, MAX(district_name) AS label, COUNT(*)::int AS count
      FROM excl_district_bbox
      WHERE district_slug IS NOT NULL
      GROUP BY district_slug
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_bbox_neighbourhoods AS (
      SELECT neighbourhood_slug AS value, MAX(neighbourhood_name) AS label, COUNT(*)::int AS count
      FROM excl_neighbourhood_bbox
      WHERE neighbourhood_slug IS NOT NULL
      GROUP BY neighbourhood_slug
      ORDER BY count DESC
      LIMIT 200
    ),
    facet_bbox_tags AS (
      SELECT t.tag AS value,
             initcap(replace(t.tag,'_',' ')) AS label,
             COUNT(*)::int AS count
      FROM (
        SELECT unnest(tags_flat) AS tag
        FROM filtered_bbox
        WHERE tags_flat IS NOT NULL
      ) t
      GROUP BY t.tag
      ORDER BY count DESC
      LIMIT 300
    ),
    facet_bbox_awards AS (
      SELECT provider AS value,
             initcap(provider) AS label,
             COUNT(DISTINCT id)::int AS count
      FROM (
        SELECT id, unnest(awards_providers) AS provider
        FROM excl_awards_bbox
        WHERE awards_providers IS NOT NULL AND cardinality(awards_providers) > 0
      ) awards_flat
      GROUP BY provider
      ORDER BY count DESC
    ),
    facet_bbox_awarded AS (
      SELECT (awards_bonus > 0) AS value, COUNT(*)::int AS count
      FROM filtered_bbox
      GROUP BY (awards_bonus > 0)
    )

    /* -----------------------------
       9) Construction du JSON final
       ----------------------------- */
    SELECT jsonb_build_object(
      'context', jsonb_build_object(
        'city', (SELECT city_slug FROM norm),
        'lang', (SELECT lang FROM norm),
        'total_global', (SELECT total_global FROM totals),
        'total_bbox',   (SELECT total_bbox   FROM totals),
        'applied_filters', jsonb_strip_nulls(jsonb_build_object(
          'parent_categories',  (SELECT parent_categories_lc  FROM norm),
          'type_keys',          (SELECT type_keys_lc          FROM norm),
          'price',              (SELECT CASE WHEN price_min IS NULL AND price_max IS NULL THEN NULL
                                             ELSE jsonb_build_object('min', price_min, 'max', price_max) END FROM norm),
          'rating',             (SELECT CASE WHEN rating_min IS NULL AND rating_max IS NULL THEN NULL
                                             ELSE jsonb_build_object('min', rating_min, 'max', rating_max) END FROM norm),
          'district_slug',      (SELECT district_slugs_lc      FROM norm),
          'neighbourhood_slug', (SELECT neighbourhood_slugs_lc FROM norm),
          'awards_providers',   (SELECT awards_providers_lc    FROM norm),
          'tags_all',           (SELECT tags_all_lc            FROM norm),
          'tags_any',           (SELECT tags_any_lc            FROM norm),
          'awarded',            p_awarded,
          'fresh',              p_fresh,
          'sort',               p_sort,
          'bbox',               (SELECT bbox_valid FROM norm)
        ))
      ),
      'facets', jsonb_build_object(
        'global', jsonb_build_object(
          'parent_categories',  COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_global_parent_categories), '[]'::jsonb),
          'type_keys',          COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'parent_category', parent_category, 'count', count)) FROM facet_global_type_keys), '[]'::jsonb),
          'price_level',        COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label',
                                            CASE value WHEN '1' THEN '€' WHEN '2' THEN '€€' WHEN '3' THEN '€€€' WHEN '4' THEN '€€€€' ELSE value END,
                                            'count', count)) FROM facet_global_price), '[]'::jsonb),
          'district_slug',      COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_global_districts), '[]'::jsonb),
          'neighbourhood_slug', COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_global_neighbourhoods), '[]'::jsonb),
          'awards',             COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_global_awards), '[]'::jsonb),
          'awarded',            COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'count', count)) FROM facet_global_awarded), '[]'::jsonb),
          'tags',               COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_global_tags), '[]'::jsonb)
        ),
        'bbox',
          CASE WHEN (SELECT bbox_valid FROM norm) IS NOT NULL THEN
            jsonb_build_object(
              'parent_categories',  COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_bbox_parent_categories), '[]'::jsonb),
              'type_keys',          COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'parent_category', parent_category, 'count', count)) FROM facet_bbox_type_keys), '[]'::jsonb),
              'price_level',        COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label',
                                                  CASE value WHEN '1' THEN '€' WHEN '2' THEN '€€' WHEN '3' THEN '€€€' WHEN '4' THEN '€€€€' ELSE value END,
                                                  'count', count)) FROM facet_bbox_price), '[]'::jsonb),
              'district_slug',      COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_bbox_districts), '[]'::jsonb),
              'neighbourhood_slug', COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_bbox_neighbourhoods), '[]'::jsonb),
              'awards',             COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_bbox_awards), '[]'::jsonb),
              'awarded',            COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'count', count)) FROM facet_bbox_awarded), '[]'::jsonb),
              'tags',               COALESCE((SELECT jsonb_agg(jsonb_build_object('value', value, 'label', label, 'count', count)) FROM facet_bbox_tags), '[]'::jsonb)
            )
          ELSE NULL
          END
      )
    )
  );
END;
$$;
