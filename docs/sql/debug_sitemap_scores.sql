-- ==================================================
-- Debug Sitemap Scores
-- ==================================================
-- Ce script aide à diagnostiquer pourquoi les scores sont à 0
-- dans l'endpoint /v1/sitemap/pois
-- ==================================================

-- 1. Vérifier combien de POIs éligibles existent
SELECT COUNT(*) as total_eligible_pois
FROM poi
WHERE publishable_status = 'eligible';

-- 2. Vérifier la structure de la vue latest_gatto_scores
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'latest_gatto_scores';

-- 3. Vérifier combien d'entrées existent dans latest_gatto_scores
SELECT COUNT(*) as total_scores
FROM latest_gatto_scores;

-- 4. Vérifier les scores pour quelques POIs éligibles
SELECT 
  p.id,
  p.slug_fr,
  p.slug_en,
  p.publishable_status,
  lgs.poi_id,
  lgs.gatto_score
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible'
ORDER BY p.updated_at DESC
LIMIT 10;

-- 5. Compter combien de POIs éligibles ont un score
SELECT 
  COUNT(DISTINCT p.id) as eligible_pois_count,
  COUNT(DISTINCT lgs.poi_id) as pois_with_scores,
  COUNT(DISTINCT p.id) - COUNT(DISTINCT lgs.poi_id) as pois_without_scores
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible';

-- 6. Voir la distribution des scores
SELECT 
  CASE 
    WHEN lgs.gatto_score IS NULL THEN 'NULL'
    WHEN lgs.gatto_score = 0 THEN '0'
    WHEN lgs.gatto_score > 0 AND lgs.gatto_score <= 20 THEN '1-20'
    WHEN lgs.gatto_score > 20 AND lgs.gatto_score <= 40 THEN '21-40'
    WHEN lgs.gatto_score > 40 AND lgs.gatto_score <= 60 THEN '41-60'
    WHEN lgs.gatto_score > 60 AND lgs.gatto_score <= 80 THEN '61-80'
    WHEN lgs.gatto_score > 80 THEN '81-100'
  END as score_range,
  COUNT(*) as count
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible'
GROUP BY score_range
ORDER BY score_range;

-- 7. Vérifier les types de colonnes et les valeurs NULL
SELECT 
  p.id as poi_id,
  p.slug_fr,
  lgs.poi_id as score_poi_id,
  lgs.gatto_score,
  pg_typeof(lgs.gatto_score) as score_type
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible'
ORDER BY p.updated_at DESC
LIMIT 5;

-- 8. Si la vue est basée sur une table, vérifier la table source
-- Adapter selon votre schéma réel
-- SELECT * FROM poi_scores ORDER BY calculated_at DESC LIMIT 10;

