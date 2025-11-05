# Déploiement du RPC `list_pois`

Ce document explique comment déployer le nouveau RPC `list_pois` optimisé pour les endpoints `/v1/pois`.

## 🎯 Objectif

Remplacer l'utilisation de `list_pois_segment` par un RPC plus simple et performant :
- ✅ Pas de cursor pagination (simple LIMIT)
- ✅ Agrégation des mentions en SQL (pas en JavaScript)
- ✅ Optimisé pour les requêtes bbox (carte + liste)
- ✅ Gain de performance : 30-50% plus rapide

## 📋 Prérequis

- Accès à Supabase SQL Editor
- Permissions pour créer des fonctions RPC
- Fonction existante : `tags_to_text_arr_deep(jsonb)` doit exister
- Vues existantes :
  - `latest_gatto_scores`
  - `latest_google_rating`

## ⚠️ Corrections importantes

**Version corrigée** : Commit `dcbc37e` (2024-11-05)

Corrections apportées :
- ✅ **Colonnes coordonnées** : Utilisation de `lat`/`lng` au lieu de `coordinates_lat`/`coordinates_lng`
- ✅ **Prix calculé inline** : `price_level_numeric` est maintenant calculé inline au lieu d'être une colonne CTE

**Important** : Utilisez la dernière version de `list_pois_rpc.sql` depuis la branch.

---

## 🚀 Étapes de déploiement

### 1. Exécuter le script SQL

Ouvrir le fichier `list_pois_rpc.sql` et exécuter son contenu dans Supabase SQL Editor :

```bash
# Copier le contenu du fichier
cat docs/sql/list_pois_rpc.sql
```

Ou directement dans Supabase SQL Editor :
1. Aller dans Supabase Dashboard > SQL Editor
2. Coller le contenu de `list_pois_rpc.sql`
3. Cliquer sur "Run"

### 2. Vérifier que le RPC est créé

```sql
-- Vérifier que la fonction existe
SELECT
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines
WHERE routine_name = 'list_pois'
  AND routine_schema = 'public';
```

Résultat attendu :
```
routine_name | routine_type | data_type
list_pois    | FUNCTION     | record
```

### 3. Tester le RPC

```sql
-- Test basique : POIs à Paris dans une bbox
SELECT * FROM list_pois(
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_city_slug := 'paris',
  p_limit := 10
);
```

Résultat attendu : 10 POIs avec leurs scores, ratings, et mentions

### 4. Tester avec filtres

```sql
-- Test avec filtres : restaurants avec terrasse
SELECT
  id,
  name,
  primary_type,
  mentions_count,
  mentions_sample
FROM list_pois(
  p_bbox := ARRAY[48.85, 2.3, 48.87, 2.4],
  p_city_slug := 'paris',
  p_primary_types := ARRAY['restaurant'],
  p_tags_any := ARRAY['terrace'],
  p_limit := 5
);
```

### 5. Vérifier les index

Le script crée automatiquement les index nécessaires. Vérifier qu'ils existent :

```sql
SELECT
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'poi'
  AND indexname IN (
    'poi_coordinates_idx',
    'poi_map_query_idx',
    'poi_primary_type_idx',
    'poi_tags_idx',
    'poi_subcategories_idx'
  );
```

## 🧪 Tests de performance

Comparer les performances avec l'ancien RPC :

```sql
-- Ancien RPC (avec segment + cursor)
EXPLAIN ANALYZE
SELECT * FROM list_pois_segment(
  p_city_slug := 'paris',
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_sort := 'gatto',
  p_segment := 'gatto',
  p_limit := 50,
  p_after_score := NULL,
  p_after_id := NULL
);

-- Nouveau RPC (optimisé)
EXPLAIN ANALYZE
SELECT * FROM list_pois(
  p_bbox := ARRAY[48.8, 2.2, 48.9, 2.4],
  p_city_slug := 'paris',
  p_sort := 'gatto',
  p_limit := 50
);
```

Gain attendu : **30-50% plus rapide**

## ⚠️ Points d'attention

### Agrégation des mentions

Le nouveau RPC agrège les mentions directement en SQL :
- `mentions_count` : COUNT de toutes les mentions
- `mentions_sample` : JSONB avec les 6 premières mentions

⚠️ **Important** : Si vous avez des POIs avec > 1000 mentions, cette agrégation peut être lente. Dans ce cas, envisager de :
1. Créer une table matérialisée pour les mentions
2. Ajouter un index sur `ai_mention(poi_id, ai_decision, published_at_guess DESC)`

### Limite de 80 POIs

Le RPC a une limite hard de 80 POIs (vs 50 pour `list_pois_segment`).

Si besoin d'augmenter :
```sql
-- Modifier la limite dans le RPC
ALTER FUNCTION list_pois(...) ...
-- Ligne 80 : v_limit INT := LEAST(GREATEST(p_limit, 1), 80);
-- Changer 80 en 100 par exemple
```

## 📊 Monitoring

Surveiller les performances du RPC :

```sql
-- Top 10 requêtes les plus lentes
SELECT
  query,
  calls,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
WHERE query LIKE '%list_pois%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

## 🔄 Rollback

En cas de problème, supprimer le RPC :

```sql
DROP FUNCTION IF EXISTS list_pois(
  FLOAT[],
  TEXT,
  TEXT[],
  TEXT[],
  TEXT[],
  TEXT[],
  TEXT[],
  TEXT[],
  TEXT[],
  INT,
  INT,
  NUMERIC,
  NUMERIC,
  BOOLEAN,
  BOOLEAN,
  TEXT,
  INT
);
```

Les anciens endpoints `/v1/poi` continueront de fonctionner avec `list_pois_segment`.

## ✅ Checklist de déploiement

- [ ] RPC `list_pois` créé dans Supabase
- [ ] Index créés et vérifiés
- [ ] Tests basiques passent (SELECT * FROM list_pois(...))
- [ ] Tests avec filtres passent
- [ ] Performance : < 200ms pour 50 POIs dans une bbox
- [ ] Endpoints `/v1/pois` fonctionnels
- [ ] Monitoring activé (pg_stat_statements)
- [ ] Documentation mise à jour

## 📞 Support

En cas de problème :
1. Vérifier les logs Supabase SQL
2. Vérifier que `tags_to_text_arr_deep` existe
3. Vérifier que les vues `latest_gatto_scores` et `latest_google_rating` existent
4. Contacter l'équipe backend

---

**Date de création** : 2024-11-05
**Auteur** : Claude
**Version** : 1.0
