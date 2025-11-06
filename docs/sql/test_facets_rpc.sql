-- =====================================================
-- Tests pour rpc_get_pois_facets (sans p_lang)
-- =====================================================
--
-- Ces requêtes testent la fonction facets avec des bbox ciblant Paris
--

-- ============================================
-- TEST 1: Bbox couvrant tout Paris (simple)
-- ============================================
-- Paris bounds: lat [48.8155, 48.9021], lng [2.2241, 2.4699]

SELECT public.rpc_get_pois_facets(
  p_city_slug := NULL,
  p_primary_types := NULL,
  p_subcategories := NULL,
  p_district_slugs := NULL,
  p_neighbourhood_slugs := NULL,
  p_tags_all := NULL,
  p_tags_any := NULL,
  p_awards_providers := NULL,
  p_price_min := NULL,
  p_price_max := NULL,
  p_rating_min := NULL,
  p_rating_max := NULL,
  p_bbox := ARRAY[48.8155, 2.2241, 48.9021, 2.4699]::numeric[],
  p_awarded := NULL,
  p_fresh := NULL,
  p_sort := 'gatto'
);

-- Attendu:
-- - context.total_bbox devrait avoir un nombre significatif de POIs
-- - facets.bbox devrait contenir des facettes pour primary_type, districts, etc.
-- - facets.global devrait aussi être présent


-- ============================================
-- TEST 2: Centre de Paris avec filtres
-- ============================================
-- Bbox plus petite: centre de Paris (autour de Notre-Dame / Marais)
-- Avec filtres: restaurants, prix modéré à cher

SELECT public.rpc_get_pois_facets(
  p_city_slug := NULL,
  p_primary_types := ARRAY['restaurant']::text[],
  p_subcategories := NULL,
  p_district_slugs := NULL,
  p_neighbourhood_slugs := NULL,
  p_tags_all := NULL,
  p_tags_any := NULL,
  p_awards_providers := NULL,
  p_price_min := 2,
  p_price_max := 3,
  p_rating_min := NULL,
  p_rating_max := NULL,
  p_bbox := ARRAY[48.8500, 2.3200, 48.8650, 2.3700]::numeric[],
  p_awarded := NULL,
  p_fresh := NULL,
  p_sort := 'rating'
);

-- Attendu:
-- - context.total_bbox devrait être filtré (uniquement restaurants prix 2-3)
-- - context.applied_filters devrait montrer les filtres appliqués
-- - facets.bbox.primary_type ne devrait contenir que "restaurant" (ou vide car filtré)
-- - facets.bbox.price_level devrait montrer la distribution des prix


-- ============================================
-- TEST 3: Montmartre avec tags et awards
-- ============================================
-- Bbox: quartier Montmartre
-- Avec filtres: awarded = true, tags spécifiques

SELECT public.rpc_get_pois_facets(
  p_city_slug := NULL,
  p_primary_types := NULL,
  p_subcategories := NULL,
  p_district_slugs := ARRAY['18e-arrondissement']::text[],
  p_neighbourhood_slugs := NULL,
  p_tags_all := NULL,
  p_tags_any := ARRAY['romantic', 'terrace']::text[],
  p_awards_providers := NULL,
  p_price_min := NULL,
  p_price_max := NULL,
  p_rating_min := 4.0,
  p_rating_max := NULL,
  p_bbox := ARRAY[48.8800, 2.3300, 48.8920, 2.3500]::numeric[],
  p_awarded := TRUE,
  p_fresh := NULL,
  p_sort := 'gatto'
);

-- Attendu:
-- - context.total_bbox devrait être très filtré
-- - context.applied_filters devrait montrer district_slug, tags_any, awarded, rating
-- - facets.bbox.awarded devrait montrer uniquement true
-- - facets.bbox.awards devrait lister les différents providers d'awards


-- ============================================
-- TEST 4: Vérification sans bbox (global only)
-- ============================================
-- Test sans bbox pour vérifier que les facettes global fonctionnent

SELECT public.rpc_get_pois_facets(
  p_city_slug := NULL,
  p_primary_types := ARRAY['cafe', 'bar']::text[],
  p_subcategories := NULL,
  p_district_slugs := NULL,
  p_neighbourhood_slugs := NULL,
  p_tags_all := NULL,
  p_tags_any := NULL,
  p_awards_providers := NULL,
  p_price_min := NULL,
  p_price_max := NULL,
  p_rating_min := NULL,
  p_rating_max := NULL,
  p_bbox := NULL,
  p_awarded := NULL,
  p_fresh := NULL,
  p_sort := 'gatto'
);

-- Attendu:
-- - context.total_global devrait avoir des résultats
-- - context.total_bbox devrait être 0 ou NULL
-- - facets.global devrait être rempli
-- - facets.bbox devrait être NULL


-- ============================================
-- VALIDATION RAPIDE
-- ============================================
-- Requête simplifiée pour vérifier que la fonction existe et répond

SELECT
  (result->'context'->'total_bbox')::int as total_pois_in_bbox,
  jsonb_array_length(result->'facets'->'bbox'->'primary_type') as nb_primary_types,
  jsonb_array_length(result->'facets'->'bbox'->'district_slug') as nb_districts
FROM (
  SELECT public.rpc_get_pois_facets(
    p_bbox := ARRAY[48.8155, 2.2241, 48.9021, 2.4699]::numeric[]
  ) as result
) t;

-- Attendu: Des nombres > 0 pour chaque colonne
