# Quick Start - Search V1 Migrations

## 🚀 Exécution rapide (ordre exact)

Copiez-collez ces fichiers **un par un** dans Supabase SQL Editor:

### 1️⃣ Extensions (~1s)
```
migrations/search_v1/001_install_extensions.sql
```

### 2️⃣a Colonnes (~2s)
```
migrations/search_v1/002a_add_name_normalized_columns.sql
```

### 2️⃣b Index (~30-60s) ⏱️
```
migrations/search_v1/002b_create_trigram_indexes.sql
```
**Note**: Peut prendre 30-60s selon la taille de votre table `poi`. C'est normal.

### 3️⃣ RPC autocomplete (~1s)
```
migrations/search_v1/005_create_autocomplete_rpc.sql
```

### 4️⃣a Drop old list_pois (~1s)
```
migrations/search_v1/006a_drop_all_list_pois.sql
```
**Important**: Cette étape supprime toutes les anciennes versions de `list_pois` pour éviter les conflits.

### 4️⃣b Update list_pois (~1s)
**IMPORTANT**: Copier-coller le contenu de `docs/sql/list_pois_rpc.sql` dans Supabase SQL Editor.

Le fichier `006_update_list_pois_rpc.sql` contient les instructions détaillées.

**Notes**:
- Les migrations 003 et 004 ne sont plus nécessaires car `poi_types` a déjà les colonnes `detection_keywords_fr` et `detection_keywords_en`.
- La fonction `list_pois` est mise à jour avec les paramètres `p_name_search` et `name_relevance_score`.

---

## ✅ Test rapide après migrations

```sql
-- 1. Test normalization
SELECT normalize_for_search('Café de l''Opéra');
-- Expected: "cafe de l'opera"

-- 2. Test detection keywords
SELECT type_key, detection_keywords_fr
FROM poi_types
WHERE 'italien' = ANY(detection_keywords_fr);
-- Expected: italian_restaurant avec ses keywords

-- 3. Test fuzzy search
SELECT name, similarity(name_normalized, 'comptoir') as sim
FROM poi
WHERE similarity(name_normalized, 'comptoir') > 0.3
ORDER BY sim DESC
LIMIT 5;
-- Expected: POIs with "Comptoir" in name

-- 4. Test list_pois with name search
SELECT name, name_relevance_score
FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoir',
  p_limit := 10
);
-- Expected: POIs matching "comptoir" with relevance scores

-- 5. Test autocomplete
SELECT * FROM autocomplete_search('ital', 'paris', 'fr', 10);
-- Expected: italian_restaurant type + POIs with "Ital" in name
```

---

## ⚠️ En cas d'erreur

### Erreur: "extension does not exist"
→ Vérifiez que vous avez bien exécuté `001_install_extensions.sql` en premier

### Erreur: "function normalize_for_search does not exist"
→ Exécutez `002a_add_name_normalized_columns.sql`

### Erreur: "relation poi_type_synonyms does not exist"
→ Exécutez `003_create_poi_type_synonyms.sql`

### Timeout lors de la création des index (002b)
→ C'est normal si vous avez beaucoup de POIs. Attendez que ça finisse (max 2-3 min).
→ Si ça timeout vraiment, contactez-moi pour une solution.

---

## 📊 Vérification complète

```sql
-- 1. Extensions installées
SELECT extname FROM pg_extension WHERE extname IN ('pg_trgm', 'unaccent');
-- Expected: 2 rows

-- 2. Colonnes créées
SELECT column_name FROM information_schema.columns
WHERE table_name = 'poi' AND column_name LIKE '%normalized%';
-- Expected: 3 rows

-- 3. Index créés
SELECT indexname FROM pg_indexes
WHERE tablename = 'poi' AND indexname LIKE '%trgm%';
-- Expected: 3 rows

-- 4. Detection keywords présents
SELECT type_key, array_length(detection_keywords_fr, 1) as nb_keywords_fr
FROM poi_types
WHERE is_active = true
LIMIT 5;
-- Expected: Types avec leurs keywords (ex: italian_restaurant → 5+ keywords)

-- 5. Fonctions créées
SELECT proname FROM pg_proc
WHERE proname IN ('normalize_for_search', 'autocomplete_search');
-- Expected: 2 rows
```

---

**Temps total estimé**: ~35-65 secondes (selon taille de votre table POI)
**Nombre de migrations**: 4 fichiers (001, 002a, 002b, 005, 006)
