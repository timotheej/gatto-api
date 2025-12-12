# Plan d'implémentation - Système de recherche V1

**Date**: 2025-12-11
**Objectif**: Recherche intelligente par nom et type (fuzzy matching)
**Scope V1**: Nom de POI + Types de cuisine (pas de geocoding)

---

## Architecture Overview

```
User Input → Parser → list_pois(params) → Results + Facets
                ↓
         Détection mode:
         - name    → p_name_search (fuzzy)
         - type    → p_type_keys (synonyms)
```

---

## Phase 1: Database Migrations

### 1.1 Installation pg_trgm
**Fichier**: `migrations/001_install_pg_trgm.sql`

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
```

**Validation**:
```sql
SELECT extname FROM pg_extension WHERE extname IN ('pg_trgm', 'unaccent');
```

### 1.2 Colonne name_normalized + Indexes
**Fichier**: `migrations/002_add_name_normalized.sql`

**Objectifs**:
- Colonne computed pour recherche sans accents
- Index trigram pour fuzzy matching
- Support multilingue (fr, en)

**DDL**:
```sql
-- Fonction helper pour normalisation
CREATE OR REPLACE FUNCTION normalize_for_search(text)
RETURNS text AS $$
  SELECT lower(unaccent(regexp_replace($1, '[''']', '''', 'g')))
$$ LANGUAGE SQL IMMUTABLE;

-- Colonnes computed
ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_normalized text
GENERATED ALWAYS AS (normalize_for_search(name)) STORED;

ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_fr_normalized text
GENERATED ALWAYS AS (normalize_for_search(name_fr)) STORED;

ALTER TABLE poi
ADD COLUMN IF NOT EXISTS name_en_normalized text
GENERATED ALWAYS AS (normalize_for_search(name_en)) STORED;

-- Index trigram (CONCURRENT pour éviter locks)
CREATE INDEX CONCURRENTLY IF NOT EXISTS poi_name_normalized_trgm_idx
ON poi USING GIN (name_normalized gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS poi_name_fr_normalized_trgm_idx
ON poi USING GIN (name_fr_normalized gin_trgm_ops);

CREATE INDEX CONCURRENTLY IF NOT EXISTS poi_name_en_normalized_trgm_idx
ON poi USING GIN (name_en_normalized gin_trgm_ops);
```

**Validation**:
```sql
-- Vérifier les colonnes
SELECT column_name, data_type, is_generated
FROM information_schema.columns
WHERE table_name = 'poi'
  AND column_name LIKE '%normalized%';

-- Vérifier les index
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'poi'
  AND indexname LIKE '%trgm%';

-- Test de performance
EXPLAIN ANALYZE
SELECT name, similarity(name_normalized, 'comptoir') as sim
FROM poi
WHERE similarity(name_normalized, 'comptoir') > 0.3
ORDER BY sim DESC
LIMIT 20;
-- Temps attendu: < 50ms
```

### 1.3 Table poi_type_synonyms
**Fichier**: `migrations/003_create_poi_type_synonyms.sql`

**Objectif**: Mapping langage naturel → type_keys

**DDL**:
```sql
CREATE TABLE IF NOT EXISTS poi_type_synonyms (
  id SERIAL PRIMARY KEY,
  type_key TEXT NOT NULL REFERENCES poi_types(type_key) ON DELETE CASCADE,
  synonym TEXT NOT NULL,
  lang TEXT NOT NULL DEFAULT 'fr',
  priority INT DEFAULT 1,  -- Pour ranking si plusieurs matchs
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(synonym, lang)
);

-- Index pour lookup rapide
CREATE INDEX poi_type_synonyms_synonym_lang_idx
ON poi_type_synonyms (synonym, lang);

CREATE INDEX poi_type_synonyms_type_key_idx
ON poi_type_synonyms (type_key);

-- Fonction helper pour matching
CREATE OR REPLACE FUNCTION find_type_by_synonym(
  p_synonym TEXT,
  p_lang TEXT DEFAULT 'fr'
) RETURNS TABLE(type_key TEXT, priority INT) AS $$
  SELECT DISTINCT type_key, priority
  FROM poi_type_synonyms
  WHERE synonym = lower(p_synonym)
    AND lang = p_lang
  ORDER BY priority DESC;
$$ LANGUAGE SQL STABLE;
```

### 1.4 Seed Synonyms
**Fichier**: `migrations/004_seed_type_synonyms.sql`

**Data**:
```sql
INSERT INTO poi_type_synonyms (type_key, synonym, lang, priority) VALUES
-- Restaurant types
('italian_restaurant', 'italien', 'fr', 10),
('italian_restaurant', 'italienne', 'fr', 10),
('italian_restaurant', 'pizza', 'fr', 8),
('italian_restaurant', 'pizzeria', 'fr', 9),
('italian_restaurant', 'trattoria', 'fr', 9),
('italian_restaurant', 'pasta', 'fr', 7),
('italian_restaurant', 'italian', 'en', 10),

('french_restaurant', 'français', 'fr', 10),
('french_restaurant', 'française', 'fr', 10),
('french_restaurant', 'bistrot', 'fr', 9),
('french_restaurant', 'brasserie', 'fr', 9),
('french_restaurant', 'french', 'en', 10),

('japanese_restaurant', 'japonais', 'fr', 10),
('japanese_restaurant', 'sushi', 'fr', 9),
('japanese_restaurant', 'ramen', 'fr', 8),
('japanese_restaurant', 'japanese', 'en', 10),

('chinese_restaurant', 'chinois', 'fr', 10),
('chinese_restaurant', 'chinese', 'en', 10),

('indian_restaurant', 'indien', 'fr', 10),
('indian_restaurant', 'indian', 'en', 10),

('thai_restaurant', 'thaï', 'fr', 10),
('thai_restaurant', 'thai', 'en', 10),

('mexican_restaurant', 'mexicain', 'fr', 10),
('mexican_restaurant', 'tacos', 'fr', 8),
('mexican_restaurant', 'mexican', 'en', 10),

('vietnamese_restaurant', 'vietnamien', 'fr', 10),
('vietnamese_restaurant', 'pho', 'fr', 8),
('vietnamese_restaurant', 'vietnamese', 'en', 10),

('korean_restaurant', 'coréen', 'fr', 10),
('korean_restaurant', 'korean', 'en', 10),

('lebanese_restaurant', 'libanais', 'fr', 10),
('lebanese_restaurant', 'lebanese', 'en', 10),

('greek_restaurant', 'grec', 'fr', 10),
('greek_restaurant', 'grecque', 'fr', 10),
('greek_restaurant', 'greek', 'en', 10),

('spanish_restaurant', 'espagnol', 'fr', 10),
('spanish_restaurant', 'tapas', 'fr', 9),
('spanish_restaurant', 'spanish', 'en', 10),

('seafood_restaurant', 'fruits de mer', 'fr', 10),
('seafood_restaurant', 'poisson', 'fr', 8),
('seafood_restaurant', 'seafood', 'en', 10),

('steakhouse', 'viande', 'fr', 8),
('steakhouse', 'grill', 'fr', 9),
('steakhouse', 'steak', 'fr', 10),

-- Bars
('cocktail_bar', 'cocktail', 'fr', 10),
('cocktail_bar', 'cocktails', 'fr', 10),
('wine_bar', 'vin', 'fr', 10),
('wine_bar', 'wine', 'en', 10),

-- Cafes
('cafe', 'café', 'fr', 10),
('cafe', 'coffee', 'en', 9),

('bakery', 'boulangerie', 'fr', 10),
('bakery', 'pain', 'fr', 8),
('bakery', 'bakery', 'en', 10),

('patisserie', 'pâtisserie', 'fr', 10),
('patisserie', 'gâteau', 'fr', 8),
('patisserie', 'pastry', 'en', 9)

ON CONFLICT (synonym, lang) DO NOTHING;
```

**Validation**:
```sql
-- Test matching
SELECT * FROM find_type_by_synonym('italien', 'fr');
SELECT * FROM find_type_by_synonym('sushi', 'fr');
SELECT * FROM find_type_by_synonym('tapas', 'fr');

-- Stats
SELECT lang, COUNT(*)
FROM poi_type_synonyms
GROUP BY lang;
```

---

## Phase 2: Modify list_pois RPC

### 2.1 Backup actuel
**Fichier**: `docs/sql/list_pois_rpc_backup_20251211.sql`

```bash
# Backup avant modification
cp docs/sql/list_pois_rpc.sql docs/sql/list_pois_rpc_backup_20251211.sql
```

### 2.2 Modifications list_pois
**Fichier**: `docs/sql/list_pois_rpc.sql`

**Changements**:

1. **Nouveaux paramètres**:
```sql
CREATE OR REPLACE FUNCTION list_pois(
  -- ... params existants ...
  p_fresh BOOLEAN DEFAULT NULL,

  -- NOUVEAUX PARAMS
  p_name_search TEXT DEFAULT NULL,
  p_name_similarity_threshold FLOAT DEFAULT 0.3,

  p_sort TEXT DEFAULT 'gatto',
  -- ...
)
```

2. **Normalisation de la query**:
```sql
WITH norm AS (
  SELECT
    -- ... existing normalizations ...
    normalize_for_search(p_name_search) AS name_search_normalized,
    p_name_similarity_threshold AS name_threshold
)
```

3. **Nouveau CTE: name_matches** (si p_name_search):
```sql
, name_matches AS (
  SELECT
    p.id,
    GREATEST(
      similarity(p.name_normalized, n.name_search_normalized),
      similarity(p.name_fr_normalized, n.name_search_normalized),
      similarity(p.name_en_normalized, n.name_search_normalized)
    ) AS name_similarity_score
  FROM poi p, norm n
  WHERE n.name_search_normalized IS NOT NULL
    AND (
      similarity(p.name_normalized, n.name_search_normalized) > n.name_threshold
      OR similarity(p.name_fr_normalized, n.name_search_normalized) > n.name_threshold
      OR similarity(p.name_en_normalized, n.name_search_normalized) > n.name_threshold
    )
)
```

4. **Modification du filtered CTE**:
```sql
, filtered AS (
  SELECT
    b.*,
    COALESCE(nm.name_similarity_score, 0) AS name_relevance
  FROM base b
  CROSS JOIN norm n
  LEFT JOIN name_matches nm ON b.id = nm.id
  WHERE
    -- ... existing filters ...

    -- NEW: Name search filter
    AND (
      n.name_search_normalized IS NULL
      OR nm.id IS NOT NULL  -- Must match name if search provided
    )
)
```

5. **Modification du tri**:
```sql
, sorted AS (
  SELECT
    *,
    CASE p_sort
      WHEN 'gatto' THEN gatto_score
      WHEN 'rating' THEN rating_value
      WHEN 'mentions' THEN mentions_count
      WHEN 'relevance' THEN name_relevance * 100  -- NEW
      WHEN 'price_asc' THEN -price_level_numeric
      WHEN 'price_desc' THEN price_level_numeric
    END AS sort_key,
    COUNT(*) OVER() AS total_count
  FROM filtered
  ORDER BY
    -- Si recherche par nom, prioriser par relevance
    CASE WHEN name_relevance > 0 THEN name_relevance ELSE 0 END DESC,
    sort_key DESC NULLS LAST,
    id ASC
  LIMIT p_limit
  OFFSET (p_page - 1) * p_limit
)
```

### 2.3 Tests RPC
**Fichier**: `tests/sql/test_list_pois_search.sql`

```sql
-- Test 1: Recherche par nom exact
SELECT COUNT(*) FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'Le Comptoir',
  p_limit := 10
);
-- Attendu: > 0

-- Test 2: Recherche avec typo
SELECT name FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoar',  -- typo
  p_limit := 5
);
-- Attendu: Contient "Comptoir"

-- Test 3: Recherche + filtres combinés
SELECT name, district_slug FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'comptoir',
  p_district_slugs := ARRAY['11e-arrondissement'],
  p_limit := 10
);
-- Attendu: Seulement 11e

-- Test 4: Performance
EXPLAIN ANALYZE
SELECT * FROM list_pois(
  p_city_slug := 'paris',
  p_name_search := 'restaurant',
  p_limit := 20
);
-- Attendu: < 100ms
```

---

## Phase 3: Search Parser & Utils

### 3.1 Structure fichiers
```
utils/
  ├── searchParser.js          (main)
  ├── searchNormalizer.js      (helpers)
  └── searchSynonyms.js        (synonym lookup)
```

### 3.2 Implémentation searchNormalizer.js
**Fichier**: `utils/searchNormalizer.js`

```javascript
/**
 * Normalise une query de recherche
 * - Lowercase
 * - Retire accents
 * - Normalise apostrophes
 * - Trim
 */
export function normalizeQuery(query) {
  if (!query || typeof query !== 'string') return '';

  return query
    .toLowerCase()
    .normalize('NFD')  // Décompose les caractères accentués
    .replace(/[\u0300-\u036f]/g, '')  // Retire les accents
    .replace(/œ/g, 'oe')
    .replace(/æ/g, 'ae')
    .replace(/['']/g, "'")  // Normalise apostrophes
    .trim();
}

/**
 * Calcule un seuil de similarité adaptatif selon la longueur
 */
export function getAdaptiveSimilarityThreshold(query) {
  const len = query.length;

  if (len <= 2) return 0.9;   // Très strict pour 1-2 lettres
  if (len <= 4) return 0.6;   // Strict pour 3-4 lettres
  if (len <= 8) return 0.4;   // Moyen pour 5-8 lettres
  return 0.3;                 // Permissif pour 9+ lettres
}

/**
 * Validation de la query
 */
export function validateQuery(query) {
  if (!query) {
    return { valid: false, error: 'Query is required' };
  }

  if (query.length < 2) {
    return { valid: false, error: 'Query must be at least 2 characters' };
  }

  if (query.length > 200) {
    return { valid: false, error: 'Query must be less than 200 characters' };
  }

  // Regex: lettres (avec accents), chiffres, espaces, tirets, apostrophes
  const validPattern = /^[a-zA-Z0-9àâäéèêëïîôùûüÿçœæÀÂÄÉÈÊËÏÎÔÙÛÜŸÇŒÆ\s\-']+$/;
  if (!validPattern.test(query)) {
    return { valid: false, error: 'Query contains invalid characters' };
  }

  return { valid: true };
}
```

### 3.3 Implémentation searchSynonyms.js
**Fichier**: `utils/searchSynonyms.js`

```javascript
/**
 * Cherche des type_keys correspondant à un mot
 * @param {string} word - Mot à chercher
 * @param {string} lang - Langue
 * @param {object} supabase - Client Supabase
 * @returns {Promise<string[]>} - Liste de type_keys
 */
export async function findTypesBySynonym(word, lang, supabase) {
  const normalized = word.toLowerCase().trim();

  const { data, error } = await supabase
    .from('poi_type_synonyms')
    .select('type_key, priority')
    .eq('synonym', normalized)
    .eq('lang', lang)
    .order('priority', { ascending: false });

  if (error || !data || data.length === 0) {
    return [];
  }

  // Retourner les type_keys (dédupliqués)
  return [...new Set(data.map(row => row.type_key))];
}

/**
 * Cherche dans les labels des types (fallback)
 */
export async function findTypesByLabel(query, lang, supabase) {
  const labelCol = lang === 'en' ? 'label_en' : 'label_fr';

  const { data, error } = await supabase
    .from('poi_types')
    .select('type_key')
    .eq('is_active', true)
    .ilike(labelCol, `%${query}%`)
    .limit(5);

  if (error || !data) return [];

  return data.map(row => row.type_key);
}

/**
 * Matching intelligent: synonymes + labels
 */
export async function matchTypes(query, lang, supabase) {
  const normalized = query.toLowerCase().trim();

  // 1. Essayer synonymes exacts
  let typeKeys = await findTypesBySynonym(normalized, lang, supabase);

  // 2. Fallback: chercher dans les labels
  if (typeKeys.length === 0) {
    typeKeys = await findTypesByLabel(normalized, lang, supabase);
  }

  return typeKeys;
}
```

### 3.4 Implémentation searchParser.js
**Fichier**: `utils/searchParser.js`

```javascript
import { normalizeQuery, validateQuery, getAdaptiveSimilarityThreshold } from './searchNormalizer.js';
import { matchTypes } from './searchSynonyms.js';

/**
 * Détecte le mode de recherche
 */
function detectSearchMode(query) {
  const normalized = query.toLowerCase();

  // V2: Adresses (désactivé pour V1)
  if (false && /\d+\s+(rue|avenue|boulevard|bd|av)/i.test(normalized)) {
    return 'address';
  }

  // V2: NLP (désactivé pour V1)
  if (false && /\b(meilleur|top|où|je veux|cherche)\b/i.test(normalized)) {
    return 'natural';
  }

  // Par défaut: recherche par nom ou type (on testera les deux)
  return 'name_or_type';
}

/**
 * Parse une query de recherche
 * @param {string} query - Query utilisateur
 * @param {string} city - Ville (pour contexte)
 * @param {string} lang - Langue
 * @param {object} supabase - Client Supabase
 * @returns {Promise<object>} - Paramètres parsés
 */
export async function parseSearchQuery(query, city = 'paris', lang = 'fr', supabase) {
  // 1. Validation
  const validation = validateQuery(query);
  if (!validation.valid) {
    throw new Error(validation.error);
  }

  // 2. Normalisation
  const normalized = normalizeQuery(query);

  // 3. Détection du mode
  const mode = detectSearchMode(normalized);

  // 4. Parse selon le mode
  switch (mode) {
    case 'address':
      // V2: À implémenter
      throw new Error('Address search not yet supported');

    case 'natural':
      // V2: À implémenter
      throw new Error('Natural language search not yet supported');

    case 'name_or_type':
    default:
      return await parseNameOrType(query, normalized, lang, supabase);
  }
}

/**
 * Parse pour nom ou type
 */
async function parseNameOrType(originalQuery, normalized, lang, supabase) {
  // 1. Tester si c'est un type connu
  const typeKeys = await matchTypes(normalized, lang, supabase);

  if (typeKeys.length > 0) {
    // C'est un type !
    return {
      mode: 'type',
      type_keys: typeKeys,
      display: originalQuery,
      original_query: originalQuery
    };
  }

  // 2. Sinon, c'est une recherche par nom
  const threshold = getAdaptiveSimilarityThreshold(normalized);

  return {
    mode: 'name',
    name_search: originalQuery,  // Garder la casse originale
    name_similarity_threshold: threshold,
    display: `POIs nommés "${originalQuery}"`,
    original_query: originalQuery
  };
}

/**
 * Cache pour le parsing (éviter lookups répétés)
 */
import { LRUCache } from 'lru-cache';

const parseCache = new LRUCache({
  max: 5000,
  ttl: 1000 * 60 * 60  // 1 heure
});

/**
 * Parse avec cache
 */
export async function parseSearchQueryCached(query, city, lang, supabase) {
  const cacheKey = `parse:${lang}:${normalizeQuery(query)}`;

  const cached = parseCache.get(cacheKey);
  if (cached) {
    return { ...cached, from_cache: true };
  }

  const result = await parseSearchQuery(query, city, lang, supabase);
  parseCache.set(cacheKey, result);

  return { ...result, from_cache: false };
}
```

---

## Phase 4: API Routes & Validation

### 4.1 Modification validation.js
**Fichier**: `utils/validation.js`

```javascript
// Ajouter au PoisQuerySchema existant
export const PoisQuerySchema = z.object({
  // ... params existants (bbox, city, etc.) ...

  // NOUVEAU: Query de recherche
  q: z.string()
    .min(2, 'Query must be at least 2 characters')
    .max(200, 'Query must be less than 200 characters')
    .regex(
      /^[a-zA-Z0-9àâäéèêëïîôùûüÿçœæÀÂÄÉÈÊËÏÎÔÙÛÜŸÇŒÆ\s\-']+$/,
      'Query contains invalid characters'
    )
    .optional(),

  // ... autres params (sort, limit, page, lang) ...
});
```

### 4.2 Modification routes/v1/pois.js
**Fichier**: `routes/v1/pois.js`

**Imports**:
```javascript
import { parseSearchQueryCached } from '../../utils/searchParser.js';
```

**Dans la route GET /pois** (ligne ~311):

```javascript
// Après validation Zod
const {
  bbox,
  city,
  q,  // NOUVEAU
  parent_categories,
  // ... etc
} = validatedQuery;

// NOUVEAU: Parser la query si présente
let searchParams = {};
if (q) {
  try {
    const startParse = Date.now();
    searchParams = await parseSearchQueryCached(
      q,
      city || 'paris',
      lang,
      fastify.supabase
    );
    const parseTime = Date.now() - startParse;

    fastify.log.info({
      query: q,
      mode: searchParams.mode,
      parseTime
    }, 'Search query parsed');

  } catch (err) {
    fastify.log.error({ query: q, error: err.message }, 'Failed to parse search query');
    return reply.code(400).send({
      success: false,
      error: 'Invalid search query',
      details: err.message,
      timestamp: new Date().toISOString()
    });
  }
}

// Merge params: explicites > parsés
const parentCategories = toArr(parent_categories);
const typeKeys = toArr(type_keys) || searchParams.type_keys || null;
// ... etc

// Appel RPC avec nouveaux params
const { data: rows, error } = await fastify.supabase.rpc('list_pois', {
  p_bbox: bboxArray,
  p_city_slug: cityParam,
  p_parent_categories: parentCategories,
  p_type_keys: typeKeys,  // Peut venir de la recherche
  // ... params existants ...

  // NOUVEAUX params
  p_name_search: searchParams.name_search || null,
  p_name_similarity_threshold: searchParams.name_similarity_threshold || 0.3,

  p_sort: sort || (searchParams.mode === 'name' ? 'relevance' : 'gatto'),
  p_limit: limit,
  p_page: page,
  p_lang: lang
});

// ... handle error et build response ...

// NOUVEAU: Ajouter search_context dans la response
const response = {
  success: true,
  data: {
    items,
    pagination: {
      total: totalCount,
      per_page: limit,
      current_page: page,
      total_pages: totalPages,
      has_next: hasNext,
      has_prev: hasPrev
    },
    // NOUVEAU
    ...(q && {
      search_context: {
        query: q,
        mode: searchParams.mode,
        display: searchParams.display,
        applied_filters: {
          ...(searchParams.type_keys && { type_keys: searchParams.type_keys }),
          ...(searchParams.name_search && { name_search: searchParams.name_search })
        },
        from_cache: searchParams.from_cache
      }
    })
  },
  timestamp: new Date().toISOString()
};
```

---

## Phase 5: Autocomplete Endpoint

### 5.1 Créer routes/v1/pois/autocomplete.js
**Fichier**: `routes/v1/pois/autocomplete.js`

```javascript
import { z } from 'zod';
import { formatZodErrors } from '../../../utils/validation.js';
import { normalizeQuery } from '../../../utils/searchNormalizer.js';

// Validation schema
const AutocompleteQuerySchema = z.object({
  q: z.string().min(1).max(100),
  city: z.string().optional().default('paris'),
  lang: z.enum(['fr', 'en']).optional().default('fr'),
  limit: z.coerce.number().int().min(1).max(20).optional().default(10)
});

export default async function autocompleteRoutes(fastify) {

  // GET /v1/pois/autocomplete
  fastify.get('/pois/autocomplete', async (request, reply) => {
    try {
      const validated = AutocompleteQuerySchema.parse(request.query);
      const { q, city, lang, limit } = validated;

      const normalized = normalizeQuery(q);

      // Appel RPC autocomplete
      const { data, error } = await fastify.supabase.rpc('autocomplete_search', {
        p_query: normalized,
        p_city_slug: city,
        p_lang: lang,
        p_limit: limit
      });

      if (error) {
        fastify.log.error('Autocomplete RPC error:', error);
        return reply.code(500).send({
          success: false,
          error: 'Autocomplete failed',
          timestamp: new Date().toISOString()
        });
      }

      // Formater les suggestions
      const suggestions = (data || []).map(row => ({
        type: row.type,
        value: row.value,
        display: row.display,
        relevance: row.relevance
      }));

      return reply.send({
        success: true,
        data: {
          query: q,
          suggestions
        },
        timestamp: new Date().toISOString()
      });

    } catch (err) {
      if (err.name === 'ZodError') {
        return reply.code(400).send({
          success: false,
          error: 'Invalid parameters',
          details: formatZodErrors(err),
          timestamp: new Date().toISOString()
        });
      }

      fastify.log.error('Autocomplete error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });
}
```

### 5.2 RPC autocomplete_search
**Fichier**: `migrations/005_create_autocomplete_rpc.sql`

```sql
CREATE OR REPLACE FUNCTION autocomplete_search(
  p_query TEXT,
  p_city_slug TEXT DEFAULT 'paris',
  p_lang TEXT DEFAULT 'fr',
  p_limit INT DEFAULT 10
) RETURNS TABLE(
  type TEXT,
  value TEXT,
  display TEXT,
  relevance FLOAT
) AS $$
BEGIN
  RETURN QUERY

  -- 1. POIs par nom (fuzzy)
  SELECT
    'poi'::TEXT AS type,
    COALESCE(slug_fr, slug_en, slug)::TEXT AS value,
    (name || ' · ' || primary_type)::TEXT AS display,
    similarity(name_normalized, normalize_for_search(p_query)) AS relevance
  FROM poi
  WHERE city_slug = p_city_slug
    AND publishable_status = 'eligible'
    AND similarity(name_normalized, normalize_for_search(p_query)) > 0.3

  UNION ALL

  -- 2. Types (via synonymes)
  SELECT DISTINCT
    'type'::TEXT AS type,
    pts.type_key::TEXT AS value,
    (pt.label_fr || ' (type)')::TEXT AS display,
    (1.0 - (LENGTH(pts.synonym) - LENGTH(p_query))::FLOAT / 10.0) AS relevance
  FROM poi_type_synonyms pts
  JOIN poi_types pt ON pts.type_key = pt.type_key
  WHERE pts.lang = p_lang
    AND pt.is_active = true
    AND pts.synonym ILIKE (p_query || '%')

  UNION ALL

  -- 3. Types (via labels)
  SELECT
    'type'::TEXT AS type,
    type_key::TEXT AS value,
    (label_fr || ' (type)')::TEXT AS display,
    similarity(label_fr, p_query) AS relevance
  FROM poi_types
  WHERE is_active = true
    AND (
      label_fr ILIKE ('%' || p_query || '%')
      OR similarity(label_fr, p_query) > 0.4
    )

  ORDER BY relevance DESC
  LIMIT p_limit;

END;
$$ LANGUAGE plpgsql STABLE;
```

### 5.3 Enregistrer la route
**Fichier**: `server.js` ou équivalent

```javascript
import autocompleteRoutes from './routes/v1/pois/autocomplete.js';

// ...
await fastify.register(autocompleteRoutes, { prefix: '/v1' });
```

---

## Phase 6: Rate Limiting & Monitoring

### 6.1 Rate Limiting
**Fichier**: `server.js`

```javascript
import rateLimit from '@fastify/rate-limit';

// Configuration globale
await fastify.register(rateLimit, {
  max: 60,              // 60 requêtes
  timeWindow: '1 minute',
  cache: 10000,
  addHeaders: {
    'x-ratelimit-limit': true,
    'x-ratelimit-remaining': true,
    'x-ratelimit-reset': true
  },
  keyGenerator: (request) => {
    // Rate limit par IP + endpoint
    return `${request.ip}:${request.url.split('?')[0]}`;
  },
  errorResponseBuilder: (request, context) => {
    return {
      success: false,
      error: 'Rate limit exceeded',
      details: `Too many requests. Try again in ${Math.ceil(context.ttl / 1000)} seconds.`,
      timestamp: new Date().toISOString()
    };
  }
});
```

### 6.2 Monitoring
**Fichier**: `utils/searchAnalytics.js`

```javascript
/**
 * Track search metrics
 */
export async function trackSearch(metrics, supabase) {
  const {
    query,
    mode,
    city,
    results_count,
    parse_time_ms,
    db_time_ms,
    total_time_ms,
    cache_hit,
    user_id,
    session_id
  } = metrics;

  // À implémenter: Logger vers votre système d'analytics
  // Ex: Posthog, Mixpanel, ou table Supabase

  try {
    await supabase.from('search_analytics').insert({
      query,
      mode,
      city,
      results_count,
      parse_time_ms,
      db_time_ms,
      total_time_ms,
      cache_hit,
      success: results_count > 0,
      user_id,
      session_id,
      created_at: new Date().toISOString()
    });
  } catch (err) {
    // Silent fail (ne pas bloquer la requête)
    console.error('Failed to track search:', err);
  }
}
```

**Table analytics** (optionnel):
```sql
CREATE TABLE IF NOT EXISTS search_analytics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  query TEXT NOT NULL,
  mode TEXT,
  city TEXT,
  results_count INT,
  parse_time_ms INT,
  db_time_ms INT,
  total_time_ms INT,
  cache_hit BOOLEAN,
  success BOOLEAN,
  user_id UUID,
  session_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX search_analytics_created_at_idx ON search_analytics (created_at DESC);
CREATE INDEX search_analytics_query_idx ON search_analytics (query);
CREATE INDEX search_analytics_success_idx ON search_analytics (success);
```

---

## Phase 7: Tests & Validation

### 7.1 Tests unitaires
**Fichier**: `tests/unit/searchParser.test.js`

```javascript
import { describe, it, expect } from 'vitest';
import { normalizeQuery, validateQuery, getAdaptiveSimilarityThreshold } from '../utils/searchNormalizer.js';

describe('searchNormalizer', () => {
  it('normalizes accents', () => {
    expect(normalizeQuery('Café')).toBe('cafe');
    expect(normalizeQuery('Crêperie')).toBe('creperie');
  });

  it('handles ligatures', () => {
    expect(normalizeQuery('Bœuf')).toBe('boeuf');
  });

  it('validates query length', () => {
    expect(validateQuery('a').valid).toBe(false);
    expect(validateQuery('ab').valid).toBe(true);
  });

  it('adapts threshold by length', () => {
    expect(getAdaptiveSimilarityThreshold('ab')).toBe(0.9);
    expect(getAdaptiveSimilarityThreshold('restaurant')).toBe(0.3);
  });
});
```

### 7.2 Tests d'intégration
**Fichier**: `tests/integration/search.test.js`

```javascript
describe('Search API', () => {
  it('searches by name', async () => {
    const res = await fetch('/v1/pois?q=comptoir&city=paris');
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.data.items.length).toBeGreaterThan(0);
    expect(json.data.search_context.mode).toBe('name');
  });

  it('searches by type', async () => {
    const res = await fetch('/v1/pois?q=italien&city=paris');
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.data.search_context.mode).toBe('type');
    expect(json.data.search_context.applied_filters.type_keys).toContain('italian_restaurant');
  });

  it('combines search + filters', async () => {
    const res = await fetch('/v1/pois?q=italien&district_slug=11e-arrondissement');
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.data.items.every(poi => poi.district === '11e-arrondissement')).toBe(true);
  });

  it('respects rate limit', async () => {
    const requests = Array(65).fill().map(() =>
      fetch('/v1/pois?q=test')
    );
    const responses = await Promise.all(requests);
    const rateLimited = responses.filter(r => r.status === 429);
    expect(rateLimited.length).toBeGreaterThan(0);
  });
});
```

### 7.3 Tests de performance
**Fichier**: `tests/performance/search_load.js`

```bash
# Artillery config
config:
  target: "http://localhost:3100"
  phases:
    - duration: 60
      arrivalRate: 10  # 10 req/sec
scenarios:
  - name: "Search by name"
    flow:
      - get:
          url: "/v1/pois?q={{ $randomString() }}&city=paris"
  - name: "Search by type"
    flow:
      - get:
          url: "/v1/pois?q=italien&city=paris"
```

---

## Checklist finale

### Migrations DB
- [ ] pg_trgm installé
- [ ] unaccent installé
- [ ] Colonnes name_normalized créées
- [ ] Index trigram créés (CONCURRENTLY)
- [ ] Table poi_type_synonyms créée
- [ ] Synonyms seedés
- [ ] RPC autocomplete_search créé
- [ ] Tests SQL validés

### Backend
- [ ] list_pois modifié et testé
- [ ] searchNormalizer.js implémenté
- [ ] searchSynonyms.js implémenté
- [ ] searchParser.js implémenté
- [ ] Validation Zod mise à jour
- [ ] Route /v1/pois modifiée
- [ ] Route /v1/pois/autocomplete créée
- [ ] Rate limiting configuré
- [ ] Monitoring ajouté
- [ ] Tests unitaires passent
- [ ] Tests d'intégration passent

### Performance
- [ ] Query par nom < 100ms
- [ ] Query par type < 50ms
- [ ] Autocomplete < 30ms
- [ ] Cache hit rate > 60%
- [ ] Load test 100 req/sec OK

### Documentation
- [ ] README.md mis à jour
- [ ] API doc mise à jour (OpenAPI/Swagger)
- [ ] Exemples d'utilisation
- [ ] Guide de migration

---

## Ordre d'implémentation recommandé

1. ✅ Migrations DB (Phase 1)
2. ✅ RPC list_pois (Phase 2)
3. ✅ Utils & Parser (Phase 3)
4. ✅ Routes API (Phase 4)
5. ✅ Autocomplete (Phase 5)
6. ✅ Rate limiting (Phase 6)
7. ✅ Tests (Phase 7)

**Durée estimée**: 2-3 jours (avec tests)
