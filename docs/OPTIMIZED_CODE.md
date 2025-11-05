# 🚀 Code optimisé - Prêt à implémenter

## 1️⃣ enrichWithPhotos optimisé (JOIN au lieu de 2 queries)

**Gain attendu** : ~10-15ms

```javascript
// À remplacer dans routes/v1/pois.js

// Enriches POIs with photos and variants (OPTIMIZED with JOIN)
async function enrichWithPhotos(fastify, poiIds, variantKeys = ['card_sq']) {
  if (!poiIds.length) return { photos: {}, variants: {} };

  // Build variant keys with all density variants
  const allVariantKeys = [];
  variantKeys.forEach(key => {
    if (!key.includes('@')) {
      allVariantKeys.push(`${key}@1x`, `${key}@2x`);
    } else {
      allVariantKeys.push(key);
    }
  });

  // OPTIMIZED: Single query with JOIN (instead of 2 sequential queries)
  const { data: photosWithVariants } = await fastify.supabase
    .from('poi_photos')
    .select(`
      id,
      poi_id,
      dominant_color,
      blurhash,
      is_primary,
      width,
      height,
      cdn_url,
      format,
      position,
      poi_photo_variants!inner (
        variant_key,
        cdn_url,
        format,
        width,
        height
      )
    `)
    .in('poi_id', poiIds)
    .eq('status', 'active')
    .in('poi_photo_variants.variant_key', allVariantKeys)
    .order('is_primary', { ascending: false })
    .order('position', { ascending: true });

  if (!photosWithVariants?.length) return { photos: {}, variants: {} };

  // Organize by poi_id and photo_id
  const photosByPoi = {};
  const variantsByPhoto = {};
  const seenPhotos = new Set();

  photosWithVariants.forEach(photo => {
    // Add photo to photosByPoi (deduplicate)
    if (!seenPhotos.has(photo.id)) {
      if (!photosByPoi[photo.poi_id]) {
        photosByPoi[photo.poi_id] = [];
      }
      photosByPoi[photo.poi_id].push({
        id: photo.id,
        poi_id: photo.poi_id,
        dominant_color: photo.dominant_color,
        blurhash: photo.blurhash,
        is_primary: photo.is_primary,
        width: photo.width,
        height: photo.height,
        cdn_url: photo.cdn_url,
        format: photo.format
      });
      seenPhotos.add(photo.id);
    }

    // Add variants
    if (photo.poi_photo_variants) {
      const variants = Array.isArray(photo.poi_photo_variants)
        ? photo.poi_photo_variants
        : [photo.poi_photo_variants];

      variants.forEach(variant => {
        if (!variantsByPhoto[photo.id]) {
          variantsByPhoto[photo.id] = [];
        }
        variantsByPhoto[photo.id].push({
          photo_id: photo.id,
          variant_key: variant.variant_key,
          cdn_url: variant.cdn_url,
          format: variant.format,
          width: variant.width,
          height: variant.height
        });
      });
    }
  });

  return { photos: photosByPoi, variants: variantsByPhoto };
}
```

---

## 2️⃣ Cache LRU in-memory

**Gain attendu** : 150ms (cache hit, ~80% des requêtes)

### **Installation**

```bash
npm install lru-cache
```

### **Code à ajouter**

```javascript
// À ajouter au début de routes/v1/pois.js

import { LRUCache } from 'lru-cache';

// Cache configuration
const poisCache = new LRUCache({
  max: 500,               // Max 500 résultats en cache
  ttl: 1000 * 60 * 5,     // 5 minutes TTL
  updateAgeOnGet: true,   // Reset TTL on cache hit
  updateAgeOnHas: false
});

// Helper pour générer une clé de cache stable
function getCacheKey(prefix, params) {
  // Trier les clés pour avoir une clé stable
  const sortedParams = Object.keys(params)
    .sort()
    .reduce((acc, key) => {
      if (params[key] !== undefined && params[key] !== null) {
        acc[key] = params[key];
      }
      return acc;
    }, {});

  return `${prefix}:${JSON.stringify(sortedParams)}`;
}
```

### **Utilisation dans GET /v1/pois**

```javascript
// Remplacer dans GET /v1/pois, après la validation du bbox

// Generate cache key
const cacheKey = getCacheKey('pois', {
  bbox: bboxArray,
  city,
  primary_type,
  subcategory,
  neighbourhood_slug,
  district_slug,
  tags,
  tags_any,
  awards,
  awarded,
  fresh,
  price_min,
  price_max,
  rating_min,
  rating_max,
  sort,
  limit: maxLimit
});

// Check cache
const cached = poisCache.get(cacheKey);
if (cached) {
  fastify.log.info({ cacheKey }, 'Cache HIT');
  reply.header('X-Cache', 'HIT');
  reply.header('Cache-Control', 'public, max-age=600');
  return reply.send(cached);
}

fastify.log.info({ cacheKey }, 'Cache MISS');

// ... existing RPC call and processing ...

// Before reply.send(), add to cache
const response = {
  success: true,
  data: {
    pois: items,
    total: items.length
  },
  timestamp: new Date().toISOString()
};

poisCache.set(cacheKey, response);
reply.header('X-Cache', 'MISS');
reply.header('Cache-Control', 'public, max-age=600');

return reply.send(response);
```

### **Utilisation dans GET /v1/pois/:slug**

```javascript
// Après const { slug } = request.params

const cacheKey = getCacheKey('poi-detail', { slug, lang });

// Check cache
const cached = poisCache.get(cacheKey);
if (cached) {
  fastify.log.info({ cacheKey }, 'Cache HIT');
  reply.header('X-Cache', 'HIT');
  reply.header('Cache-Control', 'public, max-age=600');
  return reply.send(cached);
}

fastify.log.info({ cacheKey }, 'Cache MISS');

// ... existing POI fetch and processing ...

// Before reply.send(), add to cache
const response = {
  success: true,
  data: /* ... existing response object ... */,
  timestamp: new Date().toISOString()
};

poisCache.set(cacheKey, response);
reply.header('X-Cache', 'MISS');
reply.header('Cache-Control', 'public, max-age=600');

return reply.send(response);
```

---

## 3️⃣ Index SQL pour photos

**Gain attendu** : ~5-10ms

```sql
-- À exécuter dans Supabase SQL Editor

-- Index sur poi_photos.poi_id (pour WHERE poi_id IN)
CREATE INDEX IF NOT EXISTS poi_photos_poi_id_status_idx
ON poi_photos (poi_id, status)
WHERE status = 'active';

-- Index composé pour tri optimisé
CREATE INDEX IF NOT EXISTS poi_photos_poi_sort_idx
ON poi_photos (poi_id, is_primary DESC, position ASC)
WHERE status = 'active';

-- Index sur poi_photo_variants.photo_id
CREATE INDEX IF NOT EXISTS poi_photo_variants_photo_id_idx
ON poi_photo_variants (photo_id);

-- Index composé pour filtrage par variant_key
CREATE INDEX IF NOT EXISTS poi_photo_variants_photo_variant_idx
ON poi_photo_variants (photo_id, variant_key);

-- Vérifier que les index sont créés
SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename IN ('poi_photos', 'poi_photo_variants')
ORDER BY tablename, indexname;
```

---

## 4️⃣ Monitoring des performances

```javascript
// À ajouter dans routes/v1/pois.js

// Helper pour mesurer les performances
function measurePerf(name) {
  const start = performance.now();
  return {
    end: () => {
      const duration = performance.now() - start;
      fastify.log.info({ operation: name, duration: `${duration.toFixed(2)}ms` });
      return duration;
    }
  };
}

// Utilisation dans GET /v1/pois
const timerTotal = measurePerf('GET /v1/pois - Total');

// ... after RPC call
const timerRPC = measurePerf('RPC list_pois');
const { data: rows, error } = await fastify.supabase.rpc('list_pois', { ... });
timerRPC.end();

// ... after enrichWithPhotos
const timerPhotos = measurePerf('enrichWithPhotos');
const photosData = await enrichWithPhotos(fastify, poiIds, ['card_sq']);
timerPhotos.end();

// ... at the end
timerTotal.end();
```

---

## 5️⃣ Configuration Brotli (vérifier)

```javascript
// Dans server.js, vérifier que Brotli est activé

await fastify.register(compress, {
  global: true,
  encodings: ['br', 'gzip', 'deflate'],  // br = Brotli (meilleure compression)
  threshold: 1024,  // Compresser si > 1KB
  brotliOptions: {
    params: {
      [zlib.constants.BROTLI_PARAM_MODE]: zlib.constants.BROTLI_MODE_TEXT,
      [zlib.constants.BROTLI_PARAM_QUALITY]: 4  // Balance entre vitesse et compression
    }
  }
});
```

---

## 📊 Résumé des fichiers à modifier

| Fichier | Modifications | Gain |
|---------|---------------|------|
| `routes/v1/pois.js` | enrichWithPhotos (JOIN) | ~10-15ms |
| `routes/v1/pois.js` | Cache LRU | ~150ms (hit) |
| `routes/v1/pois.js` | Monitoring | 0ms (debug) |
| Supabase SQL | Index photos | ~5-10ms |
| `server.js` | Vérifier Brotli | ~20-30ms (transfert) |

---

## 🚀 Plan de déploiement

### **Phase 1 : Tests locaux**

1. Installer lru-cache : `npm install lru-cache`
2. Modifier `routes/v1/pois.js` avec le cache
3. Modifier `enrichWithPhotos` avec le JOIN
4. Tester localement : `npm run dev`
5. Vérifier les logs de cache HIT/MISS

### **Phase 2 : Index SQL**

1. Exécuter les CREATE INDEX dans Supabase
2. Vérifier avec EXPLAIN ANALYZE
3. Comparer les performances

### **Phase 3 : Déploiement production**

1. Commit et push
2. Déployer
3. Monitorer les perfs avec les logs
4. Analyser le cache hit ratio

---

## 📈 Résultats attendus

```
AVANT optimisations :
  GET /v1/pois          : 155ms
  GET /v1/pois/:slug    :  85ms

APRÈS Phase 1 (cache + JOIN) :
  GET /v1/pois (miss)   : 130ms (-25ms, -16%)
  GET /v1/pois (hit)    :   2ms (-153ms, -98%) ⭐
  GET /v1/pois/:slug (miss) : 70ms (-15ms, -18%)
  GET /v1/pois/:slug (hit)  :  2ms (-83ms, -98%) ⭐

Cache hit ratio attendu : 80-95%
Performance moyenne   : ~20-30ms (au lieu de 155ms)
```

---

**Date** : 2025-01-05
**Auteur** : Claude
**Version** : 1.0
