# Système de Recherche V1 - Progression

**Date**: 2025-12-11
**Status**: Phase 1-3 complétées ✅ | Phase 4-7 pending

---

## ✅ Ce qui a été implémenté

### **Phase 1: Database Migrations** ✅

Fichiers créés dans [`migrations/search_v1/`](../migrations/search_v1/):

1. **001_install_extensions.sql**
   - Installation `pg_trgm` (trigram similarity)
   - Installation `unaccent` (remove accents)

2. **002_add_name_normalized_columns.sql**
   - Fonction `normalize_for_search(text)`
   - Colonnes `name_normalized`, `name_fr_normalized`, `name_en_normalized` (GENERATED)
   - Index trigram GIN sur les 3 colonnes
   - ⚡ Performance: Fuzzy search < 50ms avec index

3. **003_create_poi_type_synonyms.sql**
   - Table `poi_type_synonyms` (mapping synonymes → type_keys)
   - Fonction helper `find_type_by_synonym(synonym, lang)`
   - Index optimisés pour lookup rapide

4. **004_seed_type_synonyms.sql**
   - **~130+ synonymes** seedés pour types courants
   - Français + Anglais
   - Exemples: "italien" → italian_restaurant, "sushi" → japanese_restaurant

5. **005_create_autocomplete_rpc.sql**
   - Fonction `autocomplete_search(query, city, lang, limit)`
   - Retourne: POIs + Types matchant la query
   - 3 sources: fuzzy POI names, synonym prefix match, label search
   - ⚡ Performance cible: < 30ms

6. **006_update_list_pois_rpc.sql**
   - Migration pour déployer le nouveau RPC

---

### **Phase 2: Modified list_pois RPC** ✅

Fichier modifié: [`docs/sql/list_pois_rpc.sql`](../docs/sql/list_pois_rpc.sql)
Backup: [`docs/sql/list_pois_rpc_backup_20251211.sql`](../docs/sql/list_pois_rpc_backup_20251211.sql)

**Nouveaux paramètres**:
```sql
p_name_search TEXT DEFAULT NULL,                -- Query for fuzzy name matching
p_name_similarity_threshold FLOAT DEFAULT 0.3,  -- Similarity threshold (0-1)
```

**Nouvelle colonne retournée**:
```sql
name_relevance_score FLOAT  -- Similarity score (0-1) for name matches
```

**Nouveau tri**:
```sql
p_sort := 'relevance'  -- Sort by name similarity score
```

**Logique ajoutée**:
1. **CTE `norm`**: Normalise `p_name_search` avec `normalize_for_search()`
2. **CTE `name_matches`**: Calcule similarity scores via trigram
3. **CTE `base`**: JOIN avec `name_matches`, ajoute `name_relevance_score`
4. **CTE `filtered`**: Filtre POIs où `name_relevance_score > 0` si recherche active
5. **CTE `sorted`**: Tri prioritaire par `name_relevance_score` si recherche par nom

**Exemples d'utilisation**:
```sql
-- Recherche simple
SELECT * FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoir',
  p_limit := 20
);

-- Recherche + filtres
SELECT * FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoir',
  p_district_slugs := ARRAY['11e-arrondissement'],
  p_price_min := 2,
  p_limit := 10
);

-- Recherche avec typo (fuzzy)
SELECT name, name_relevance_score FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoar',  -- typo!
  p_limit := 5
);
-- Retournera quand même "Le Comptoir" grâce au fuzzy matching
```

---

### **Phase 3: Search Parser & Utilities** ✅

Fichiers créés dans [`utils/`](../utils/):

#### **1. searchNormalizer.js**

Fonctions exportées:
- `normalizeQuery(query)` - Normalise accents, casse, ligatures
- `validateQuery(query)` - Validation (length, chars)
- `getAdaptiveSimilarityThreshold(query)` - Seuil adaptatif selon longueur
- `sanitizeQuery(query)` - Validation + normalisation

Exemples:
```javascript
normalizeQuery("Café de l'Opéra")
// → "cafe de l'opera"

getAdaptiveSimilarityThreshold("ab")
// → 0.9 (strict pour 2 chars)

getAdaptiveSimilarityThreshold("restaurant italien")
// → 0.3 (permissif pour query longue)
```

#### **2. searchSynonyms.js**

Fonctions exportées:
- `findTypesBySynonym(word, lang, supabase)` - Exact synonym match
- `findTypesByLabel(query, lang, supabase)` - Fallback via labels
- `matchTypes(query, lang, supabase)` - Intelligent matching (synonyms first)
- `isKnownType(query, lang, supabase)` - Boolean check

Exemples:
```javascript
await matchTypes('italien', 'fr', supabase)
// → ['italian_restaurant']

await matchTypes('sushi', 'fr', supabase)
// → ['japanese_restaurant']

await matchTypes('xyz123', 'fr', supabase)
// → [] (no match)
```

#### **3. searchParser.js**

Fonctions exportées:
- `parseSearchQuery(query, city, lang, supabase)` - Main parser
- `parseSearchQueryCached(...)` - Version avec cache (1h TTL)
- `clearParseCache()` - Clear cache
- `getParseCacheStats()` - Cache stats

Flow:
```
Query → Validate → Normalize → Detect Mode → Parse → Return Params
```

Modes détectés (V1):
- `name_or_type`: Teste synonym match, sinon name search

Modes désactivés (V2):
- `address`: Geocoding (à implémenter)
- `natural`: NLP (à implémenter)

Exemples:
```javascript
// Type match
await parseSearchQuery('italien', 'paris', 'fr', supabase)
// → {
//   mode: 'type',
//   type_keys: ['italian_restaurant'],
//   display: 'italien',
//   original_query: 'italien'
// }

// Name search
await parseSearchQuery('Le Comptoir', 'paris', 'fr', supabase)
// → {
//   mode: 'name',
//   name_search: 'Le Comptoir',
//   name_similarity_threshold: 0.4,
//   display: 'POIs nommés "Le Comptoir"',
//   original_query: 'Le Comptoir'
// }
```

**Cache**: LRU 5000 entries, TTL 1h
- Évite lookups répétés (ex: "italien" recherché 100x)
- Réduit charge DB

---

## 🔨 Prochaines étapes (Phases 4-7)

### **Phase 4: Update API Routes** (Pending)
- [ ] Modifier `utils/validation.js` (ajouter param `?q=` au schema Zod)
- [ ] Modifier `routes/v1/pois.js` (intégrer parser + appel RPC)
- [ ] Ajouter `search_context` dans la response
- [ ] Tests d'intégration

### **Phase 5: Autocomplete Endpoint** (Pending)
- [ ] Créer `routes/v1/pois/autocomplete.js`
- [ ] Validation Zod
- [ ] Appel RPC `autocomplete_search`
- [ ] Tests

### **Phase 6: Rate Limiting & Monitoring** (Pending)
- [ ] Rate limiting (60/min par IP)
- [ ] Monitoring/analytics
- [ ] Logging des métriques de recherche

### **Phase 7: Testing & Validation** (Pending)
- [ ] Tests unitaires (utils)
- [ ] Tests d'intégration (API)
- [ ] Tests de performance (< 100ms)
- [ ] Load testing (100 req/s)

---

## 🚀 Comment tester (après migrations DB)

### **1. Exécuter les migrations dans Supabase SQL Editor**

Dans l'ordre:
```bash
migrations/search_v1/001_install_extensions.sql
migrations/search_v1/002_add_name_normalized_columns.sql
migrations/search_v1/003_create_poi_type_synonyms.sql
migrations/search_v1/004_seed_type_synonyms.sql
migrations/search_v1/005_create_autocomplete_rpc.sql
migrations/search_v1/006_update_list_pois_rpc.sql
```

Voir: [migrations/search_v1/README.md](../migrations/search_v1/README.md)

### **2. Tests SQL directs**

```sql
-- Test 1: Fuzzy search par nom
SELECT name, name_relevance_score
FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoir',
  p_limit := 10
);

-- Test 2: Synonym match (italien)
SELECT * FROM find_type_by_synonym('italien', 'fr');
-- Expected: italian_restaurant

-- Test 3: Autocomplete
SELECT * FROM autocomplete_search('ital', 'paris', 'fr', 10);
-- Expected: italian_restaurant + POIs avec "Ital" dans le nom

-- Test 4: Performance
EXPLAIN ANALYZE
SELECT * FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'restaurant',
  p_limit := 20
);
-- Expected: Uses trigram index, < 100ms
```

### **3. Tests Node.js (utils)**

```javascript
import { parseSearchQueryCached } from './utils/searchParser.js';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

// Test type match
const result1 = await parseSearchQueryCached('italien', 'paris', 'fr', supabase);
console.log(result1);
// { mode: 'type', type_keys: ['italian_restaurant'], ... }

// Test name search
const result2 = await parseSearchQueryCached('Le Comptoir', 'paris', 'fr', supabase);
console.log(result2);
// { mode: 'name', name_search: 'Le Comptoir', ... }
```

---

## 📁 Structure des fichiers créés

```
gatto-api/
├── docs/
│   ├── IMPLEMENTATION_PLAN_SEARCH.md  ← Plan détaillé complet
│   ├── SEARCH_V1_PROGRESS.md          ← Ce fichier (progression)
│   └── sql/
│       ├── list_pois_rpc.sql          ← Modifié (avec name search)
│       └── list_pois_rpc_backup_20251211.sql  ← Backup
│
├── migrations/
│   └── search_v1/
│       ├── README.md                  ← Guide d'exécution
│       ├── 001_install_extensions.sql
│       ├── 002_add_name_normalized_columns.sql
│       ├── 003_create_poi_type_synonyms.sql
│       ├── 004_seed_type_synonyms.sql
│       ├── 005_create_autocomplete_rpc.sql
│       └── 006_update_list_pois_rpc.sql
│
└── utils/
    ├── searchNormalizer.js            ← Normalisation + validation
    ├── searchSynonyms.js              ← Type matching
    └── searchParser.js                ← Main parser + cache
```

---

## 🎯 Checklist avant de passer à Phase 4

- [x] Migrations DB créées
- [x] RPC list_pois modifié
- [x] Utils créés et documentés
- [x] Backup de list_pois
- [x] Plan d'implémentation complet
- [ ] **Migrations exécutées sur Supabase** ← À FAIRE
- [ ] **Tests SQL validés** ← À FAIRE
- [ ] **Tests utils validés** ← À FAIRE

---

## 💡 Notes importantes

### Performance attendue
- Fuzzy search: < 50ms avec index trigram
- Autocomplete: < 30ms
- Synonym lookup: < 10ms (cached)
- Parser: < 5ms (cached)

### Cache strategy
- **Parse cache**: 5000 entries, TTL 1h (réduit lookups DB)
- **POI cache** (existant): Pas modifié, fonctionne normalement

### Backward compatibility
- ✅ Tous les params existants de `list_pois` fonctionnent
- ✅ `p_name_search` est optionnel (NULL par défaut)
- ✅ Si `p_name_search` = NULL, comportement identique à avant
- ✅ Pas de breaking changes

### Sécurité
- Validation stricte des queries (Zod + utils)
- Rate limiting recommandé (60/min)
- Pas d'injection SQL (parameterized queries)
- Cache DoS protection (max 5000 entries)

---

**Prochaine action**: Exécuter les migrations DB puis passer à Phase 4 (API routes).
