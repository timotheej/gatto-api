# Search V1 Migrations

Database migrations pour le système de recherche intelligent (nom + type).

## Order d'exécution

**IMPORTANT**: Exécuter dans cet ordre exact via Supabase SQL Editor.

### 1. Install extensions
```bash
migrations/search_v1/001_install_extensions.sql
```

**Vérification**:
```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pg_trgm', 'unaccent');
```

### 2a. Add normalized columns (FAST - ~2s)
```bash
migrations/search_v1/002a_add_name_normalized_columns.sql
```

**Vérification**:
```sql
-- Check columns
SELECT column_name, is_generated
FROM information_schema.columns
WHERE table_name = 'poi' AND column_name LIKE '%normalized%';

-- Test normalization
SELECT name, name_normalized FROM poi LIMIT 5;
```

### 2b. Create trigram indexes (SLOW - ~30-60s)
```bash
migrations/search_v1/002b_create_trigram_indexes.sql
```

**Vérification**:
```sql
-- Check indexes
SELECT indexname FROM pg_indexes
WHERE tablename = 'poi' AND indexname LIKE '%trgm%';
-- Expected: 3 indexes

-- Test fuzzy search
SELECT name, similarity(name_normalized, 'comptoir') as sim
FROM poi
WHERE similarity(name_normalized, 'comptoir') > 0.3
ORDER BY sim DESC
LIMIT 5;
```

**Note**: Les migrations 003 et 004 (synonyms table) ne sont plus nécessaires. La table `poi_types` contient déjà les colonnes `detection_keywords_fr` et `detection_keywords_en` avec les mots-clés de détection.

### 3. Create autocomplete RPC
```bash
migrations/search_v1/005_create_autocomplete_rpc.sql
```

**Vérification**:
```sql
-- Test autocomplete
SELECT * FROM autocomplete_search('ital', 'paris', 'fr', 10);
-- Expected: italian_restaurant + POIs with "Ital" in name

-- Performance test
EXPLAIN ANALYZE
SELECT * FROM autocomplete_search('rest', 'paris', 'fr', 10);
-- Expected: < 50ms
```

---

## Tests complets

Après toutes les migrations:

```sql
-- Test 1: Fuzzy search on POI names
SELECT name, similarity(name_normalized, 'comptoir') as sim
FROM poi
WHERE similarity(name_normalized, 'comptoir') > 0.3
ORDER BY sim DESC
LIMIT 10;

-- Test 2: Detection keywords lookup
SELECT type_key, detection_keywords_fr
FROM poi_types
WHERE 'italien' = ANY(detection_keywords_fr);

-- Test 3: Autocomplete
SELECT type, value, display, relevance
FROM autocomplete_search('sush', 'paris', 'fr', 10)
ORDER BY relevance DESC;

-- Test 4: Performance (doit utiliser index trigram)
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM poi
WHERE similarity(name_normalized, 'restaurant') > 0.3
LIMIT 20;
-- Vérifier "Bitmap Index Scan" sur poi_name_normalized_trgm_idx
```

---

## Rollback (si nécessaire)

```sql
-- ATTENTION: Supprime toutes les données et index créés

-- Drop autocomplete RPC
DROP FUNCTION IF EXISTS autocomplete_search(TEXT, TEXT, TEXT, INT);

-- Drop indexes (CONCURRENT pour éviter locks)
DROP INDEX CONCURRENTLY IF EXISTS poi_name_normalized_trgm_idx;
DROP INDEX CONCURRENTLY IF EXISTS poi_name_fr_normalized_trgm_idx;
DROP INDEX CONCURRENTLY IF EXISTS poi_name_en_normalized_trgm_idx;

-- Drop columns
ALTER TABLE poi DROP COLUMN IF EXISTS name_normalized;
ALTER TABLE poi DROP COLUMN IF EXISTS name_fr_normalized;
ALTER TABLE poi DROP COLUMN IF EXISTS name_en_normalized;

-- Drop helper function
DROP FUNCTION IF EXISTS normalize_for_search(TEXT);

-- Drop extensions (optionnel, peut être utilisé ailleurs)
-- DROP EXTENSION IF EXISTS pg_trgm;
-- DROP EXTENSION IF EXISTS unaccent;
```

---

## Troubleshooting

### Erreur: "extension does not exist"
```sql
-- Vérifier les extensions disponibles
SELECT * FROM pg_available_extensions
WHERE name IN ('pg_trgm', 'unaccent');

-- Si pas disponible, contacter support Supabase
```

### Erreur: "index already exists"
```sql
-- Lister les index existants
SELECT indexname FROM pg_indexes WHERE tablename = 'poi';

-- Supprimer si conflit
DROP INDEX IF EXISTS poi_name_normalized_trgm_idx;
-- Puis re-run la migration
```

### Performance lente sur CREATE INDEX
```sql
-- Les index trigram peuvent prendre 30s-1min sur 10k POIs
-- C'est normal, CONCURRENTLY permet de ne pas bloquer les queries

-- Vérifier la progression:
SELECT
  relname,
  CASE
    WHEN reltuples > 0 THEN (n_tup_ins / reltuples * 100)::INT
    ELSE 0
  END AS progress_pct
FROM pg_stat_user_tables
WHERE relname = 'poi';
```

### Detection keyword manquant
```sql
-- Vérifier les keywords d'un type
SELECT type_key, detection_keywords_fr, detection_keywords_en
FROM poi_types
WHERE type_key = 'italian_restaurant';

-- Ajouter un keyword manuellement (si nécessaire)
UPDATE poi_types
SET detection_keywords_fr = array_append(detection_keywords_fr, 'nouveau_mot')
WHERE type_key = 'italian_restaurant';
```

---

## Next Steps

Après les migrations DB:
1. ✅ Modifier `list_pois` RPC (Phase 2)
2. ✅ Créer `utils/searchParser.js` (Phase 3)
3. ✅ Modifier routes API (Phase 4)

Voir: [IMPLEMENTATION_PLAN_SEARCH.md](../../docs/IMPLEMENTATION_PLAN_SEARCH.md)
