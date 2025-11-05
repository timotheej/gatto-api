-- ==================================================
-- Tests pour le RPC list_pois
-- ==================================================
-- Exécuter ces tests après avoir déployé le RPC
-- ==================================================

-- 1. Vérifier que la fonction existe
SELECT
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines
WHERE routine_name = 'list_pois'
  AND routine_schema = 'public';

-- Résultat attendu:
-- routine_name | routine_type | data_type
-- list_pois    | FUNCTION     | record


-- 2. Vérifier que les index existent
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'poi'
  AND indexname IN (
    'poi_lat_lng_idx',
    'poi_map_query_idx',
    'poi_primary_type_idx',
    'poi_tags_idx',
    'poi_subcategories_idx',
    'poi_neighbourhood_slug_idx',
    'poi_district_slug_idx',
    'poi_price_level_numeric_idx'
  );

-- Résultat attendu: 8 rows (un pour chaque index)


-- 3. Test basique : 10 POIs à Paris
SELECT
  id,
  name,
  lat,
  lng,
  primary_type,
  gatto_score,
  mentions_count
FROM list_pois(
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_city_slug := 'paris',
  p_limit := 10
);

-- Résultat attendu: 10 POIs avec leurs données


-- 4. Test avec filtres : restaurants avec terrasse
SELECT
  id,
  name,
  primary_type,
  tags_flat,
  mentions_count,
  mentions_sample
FROM list_pois(
  p_bbox := ARRAY[48.85, 2.3, 48.87, 2.4],
  p_city_slug := 'paris',
  p_primary_types := ARRAY['restaurant'],
  p_tags_any := ARRAY['terrace'],
  p_limit := 5
);

-- Résultat attendu: 5 restaurants avec le tag "terrace"


-- 5. Test de performance : mesurer le temps d'exécution
EXPLAIN ANALYZE
SELECT * FROM list_pois(
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_city_slug := 'paris',
  p_limit := 50
);

-- Résultat attendu: Execution time < 200ms


-- 6. Test mentions_sample : vérifier le format JSONB
SELECT
  id,
  name,
  mentions_count,
  jsonb_array_length(mentions_sample) as sample_length,
  jsonb_pretty(mentions_sample) as sample_preview
FROM list_pois(
  p_bbox := ARRAY[48.85, 2.3, 48.87, 2.4],
  p_city_slug := 'paris',
  p_limit := 3
)
WHERE mentions_count > 0;

-- Résultat attendu: mentions_sample doit être un JSONB valide avec max 6 éléments


-- 7. Test tous les filtres combinés
SELECT
  id,
  name,
  primary_type,
  price_level,
  rating_value,
  mentions_count
FROM list_pois(
  p_bbox := ARRAY[48.85, 2.3, 48.87, 2.4],
  p_city_slug := 'paris',
  p_primary_types := ARRAY['restaurant'],
  p_price_min := 2,
  p_price_max := 3,
  p_rating_min := 4.0,
  p_tags_any := ARRAY['terrace', 'romantic'],
  p_sort := 'rating',
  p_limit := 10
);

-- Résultat attendu: Max 10 restaurants avec price 2-3, rating >= 4.0, avec tag terrace OU romantic


-- 8. Test bbox invalide (doit échouer)
SELECT * FROM list_pois(
  p_bbox := ARRAY[48.9, 2.2, 48.8, 2.4],  -- lat_min > lat_max (invalide)
  p_city_slug := 'paris',
  p_limit := 10
);

-- Résultat attendu: ERREUR "bbox min must be less than max"


-- 9. Comparer avec l'ancien RPC (si disponible)
-- ATTENTION: Ne lancer que si list_pois_segment existe encore
/*
EXPLAIN ANALYZE
SELECT * FROM list_pois_segment(
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_city_slug := 'paris',
  p_sort := 'gatto',
  p_segment := 'gatto',
  p_limit := 50,
  p_after_score := NULL,
  p_after_id := NULL
);
*/

-- Comparer le temps d'exécution avec le test #5


-- 10. Test des colonnes retournées
SELECT
  column_name,
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'poi'
  AND column_name IN ('lat', 'lng', 'coordinates_lat', 'coordinates_lng');

-- Résultat attendu: Uniquement 'lat' et 'lng' doivent exister
-- Si 'coordinates_lat' ou 'coordinates_lng' existent, c'est un problème


-- ==================================================
-- Résumé des tests
-- ==================================================
-- ✅ Test 1: Fonction existe
-- ✅ Test 2: Index créés
-- ✅ Test 3: Requête basique fonctionne
-- ✅ Test 4: Filtres fonctionnent
-- ✅ Test 5: Performance < 200ms
-- ✅ Test 6: mentions_sample est un JSONB valide
-- ✅ Test 7: Tous les filtres combinés
-- ✅ Test 8: Validation bbox fonctionne
-- ✅ Test 10: Colonnes lat/lng existent
