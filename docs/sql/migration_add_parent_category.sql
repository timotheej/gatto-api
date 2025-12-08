-- =====================================================
-- Migration: Ajouter parent_category à poi_types
-- =====================================================
-- Date: 2025-12-08
-- Description: Ajoute la colonne parent_category pour regrouper
--              les types en catégories UX simplifiées
--
-- OBJECTIF: 220+ entrées doivent TOUTES avoir une parent_category
-- =====================================================

-- =====================================================
-- ÉTAPE 1: Ajout de la colonne
-- =====================================================

ALTER TABLE public.poi_types
ADD COLUMN IF NOT EXISTS parent_category TEXT;

-- =====================================================
-- ÉTAPE 2: Population de parent_category
-- =====================================================
-- Mapping exhaustif de TOUS les category_group existants

-- ============ RESTAURANT (6 sous-groupes) ============
-- Groupe: Cuisines (italien, coréen, indien, etc.)
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_cuisine'
  AND parent_category IS NULL;

-- Groupe: Spécialités (pizza, sushi, burger, etc.)
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_specialty'
  AND parent_category IS NULL;

-- Groupe: Concepts (bistro, brasserie, trattoria, etc.)
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_concept'
  AND parent_category IS NULL;

-- Groupe: Services (fast-food, fine-dining, buffet, etc.)
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_service'
  AND parent_category IS NULL;

-- Groupe: Moments de repas (brunch, breakfast)
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_meal_type'
  AND parent_category IS NULL;

-- Groupe: Restaurant générique
UPDATE public.poi_types
SET parent_category = 'restaurant'
WHERE category_group = 'restaurant_generic'
  AND parent_category IS NULL;

-- ============ BAR (4 sous-groupes) ============
-- Groupe: Bars spécialisés (wine bar, cocktail bar, etc.)
UPDATE public.poi_types
SET parent_category = 'bar'
WHERE category_group = 'bar_specialty'
  AND parent_category IS NULL;

-- Groupe: Concepts de bar (pub, rooftop, speakeasy, etc.)
UPDATE public.poi_types
SET parent_category = 'bar'
WHERE category_group = 'bar_concept'
  AND parent_category IS NULL;

-- Groupe: Bar générique
UPDATE public.poi_types
SET parent_category = 'bar'
WHERE category_group = 'bar_generic'
  AND parent_category IS NULL;

-- Groupe: Bar hybride (bar-grill)
UPDATE public.poi_types
SET parent_category = 'bar'
WHERE category_group = 'bar_hybrid'
  AND parent_category IS NULL;

-- ============ CAFE ============
UPDATE public.poi_types
SET parent_category = 'cafe'
WHERE category_group = 'cafe'
  AND parent_category IS NULL;

-- ============ BAKERY ============
UPDATE public.poi_types
SET parent_category = 'bakery'
WHERE category_group = 'bakery'
  AND parent_category IS NULL;

-- ============ DESSERT ============
UPDATE public.poi_types
SET parent_category = 'dessert'
WHERE category_group = 'dessert_specialty'
  AND parent_category IS NULL;

-- ============ FOOD (2 sous-groupes) ============
-- Commerce alimentaire (épicerie, boucherie, fromagerie, etc.)
UPDATE public.poi_types
SET parent_category = 'food_retail'
WHERE category_group = 'food_retail'
  AND parent_category IS NULL;

-- Services alimentaires (traiteur, catering)
UPDATE public.poi_types
SET parent_category = 'food_retail'
WHERE category_group = 'food_service'
  AND parent_category IS NULL;

-- ============ NIGHTLIFE ============
UPDATE public.poi_types
SET parent_category = 'nightlife'
WHERE category_group = 'nightlife'
  AND parent_category IS NULL;

-- ============ LODGING ============
UPDATE public.poi_types
SET parent_category = 'lodging'
WHERE category_group = 'lodging'
  AND parent_category IS NULL;

-- ============ CULTURE ============
UPDATE public.poi_types
SET parent_category = 'culture'
WHERE category_group = 'culture'
  AND parent_category IS NULL;

-- ============ ENTERTAINMENT ============
UPDATE public.poi_types
SET parent_category = 'entertainment'
WHERE category_group = 'entertainment'
  AND parent_category IS NULL;

-- ============ WELLNESS ============
UPDATE public.poi_types
SET parent_category = 'wellness'
WHERE category_group = 'wellness'
  AND parent_category IS NULL;

-- ============ HEALTH ============
UPDATE public.poi_types
SET parent_category = 'health'
WHERE category_group = 'health'
  AND parent_category IS NULL;

-- ============ SPORTS ============
UPDATE public.poi_types
SET parent_category = 'sports'
WHERE category_group = 'sports_fitness'
  AND parent_category IS NULL;

-- ============ RETAIL ============
UPDATE public.poi_types
SET parent_category = 'retail'
WHERE category_group = 'retail'
  AND parent_category IS NULL;

-- ============ SERVICES ============
UPDATE public.poi_types
SET parent_category = 'services'
WHERE category_group = 'services'
  AND parent_category IS NULL;

-- ============ AUTOMOTIVE ============
UPDATE public.poi_types
SET parent_category = 'automotive'
WHERE category_group = 'automotive'
  AND parent_category IS NULL;

-- ============ TRANSPORT ============
UPDATE public.poi_types
SET parent_category = 'transport'
WHERE category_group = 'transport'
  AND parent_category IS NULL;

-- ============ PARKS & NATURE ============
UPDATE public.poi_types
SET parent_category = 'parks'
WHERE category_group = 'parks_nature'
  AND parent_category IS NULL;

-- ============ GOVERNMENT ============
UPDATE public.poi_types
SET parent_category = 'government'
WHERE category_group = 'government'
  AND parent_category IS NULL;

-- ============ EDUCATION ============
UPDATE public.poi_types
SET parent_category = 'education'
WHERE category_group = 'education'
  AND parent_category IS NULL;

-- ============ FINANCE ============
UPDATE public.poi_types
SET parent_category = 'finance'
WHERE category_group = 'finance'
  AND parent_category IS NULL;

-- ============ GENERIC (types non-catégorisables) ============
UPDATE public.poi_types
SET parent_category = 'other'
WHERE category_group = 'generic'
  AND parent_category IS NULL;

-- =====================================================
-- ÉTAPE 3: Validation STRICTE
-- =====================================================

-- Vérifier qu'AUCUNE ligne n'a parent_category NULL
DO $$
DECLARE
  v_null_count INTEGER;
  v_total_count INTEGER;
BEGIN
  -- Compter les NULL
  SELECT COUNT(*) INTO v_null_count
  FROM public.poi_types
  WHERE parent_category IS NULL AND is_active = true;

  -- Compter le total
  SELECT COUNT(*) INTO v_total_count
  FROM public.poi_types
  WHERE is_active = true;

  -- Lever une erreur si des NULL existent
  IF v_null_count > 0 THEN
    RAISE EXCEPTION 'MIGRATION ÉCHOUÉE: % entrées actives sans parent_category sur % total',
      v_null_count, v_total_count;
  END IF;

  RAISE NOTICE 'SUCCÈS: Toutes les % entrées actives ont une parent_category', v_total_count;
END $$;

-- =====================================================
-- ÉTAPE 4: Contraintes et index
-- =====================================================

-- Ajouter contrainte NOT NULL (après population)
ALTER TABLE public.poi_types
ALTER COLUMN parent_category SET NOT NULL;

-- Ajouter contrainte de validation (valeurs autorisées)
ALTER TABLE public.poi_types
ADD CONSTRAINT poi_types_parent_category_check
CHECK (parent_category IN (
  'restaurant',
  'bar',
  'cafe',
  'bakery',
  'dessert',
  'food_retail',
  'nightlife',
  'lodging',
  'culture',
  'entertainment',
  'wellness',
  'health',
  'sports',
  'retail',
  'services',
  'automotive',
  'transport',
  'parks',
  'government',
  'education',
  'finance',
  'other'
));

-- Créer index pour les requêtes de facettes
CREATE INDEX IF NOT EXISTS idx_poi_types_parent_category
ON public.poi_types(parent_category)
WHERE is_active = true;

-- Créer index composite pour hiérarchie complète
CREATE INDEX IF NOT EXISTS idx_poi_types_parent_type
ON public.poi_types(parent_category, type_key)
WHERE is_active = true;

-- =====================================================
-- ÉTAPE 5: Rapport de validation détaillé
-- =====================================================

-- Rapport par parent_category
SELECT
  parent_category,
  COUNT(*) as count,
  array_agg(DISTINCT category_group ORDER BY category_group) as category_groups_mapped,
  array_agg(DISTINCT source ORDER BY source) as sources
FROM public.poi_types
WHERE is_active = true
GROUP BY parent_category
ORDER BY count DESC;

-- Vérification des category_group non mappés (devrait être vide)
SELECT
  category_group,
  COUNT(*) as count,
  array_agg(type_key ORDER BY type_key LIMIT 3) as examples
FROM public.poi_types
WHERE parent_category IS NULL
  AND is_active = true
GROUP BY category_group;

-- Total final
SELECT
  COUNT(*) as total_entries,
  COUNT(*) FILTER (WHERE parent_category IS NOT NULL) as with_parent_category,
  COUNT(*) FILTER (WHERE parent_category IS NULL) as without_parent_category,
  ROUND(100.0 * COUNT(*) FILTER (WHERE parent_category IS NOT NULL) / COUNT(*), 2) as percentage_complete
FROM public.poi_types
WHERE is_active = true;

-- =====================================================
-- ROLLBACK (si nécessaire)
-- =====================================================
-- Pour annuler cette migration, exécuter:
-- ALTER TABLE public.poi_types DROP COLUMN IF EXISTS parent_category CASCADE;
