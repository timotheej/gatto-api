# Testing Phase 1 Optimizations - Guide

## 📋 Prérequis

1. **Déployer les indexes SQL** (important !)
   ```sql
   -- Copier et exécuter le contenu de docs/sql/photo_indexes.sql
   -- dans Supabase SQL Editor
   ```

2. **Redémarrer l'API** après avoir déployé les indexes

3. **Avoir des données de test** avec bbox connus

---

## 🧪 Tests à effectuer

### Test 1: GET /v1/pois (Liste avec bbox - map view)

#### Requête de test
```bash
# Exemple avec bbox de Paris
curl -v "http://localhost:3000/v1/pois?bbox=2.25,48.81,2.42,48.90" \
  -H "Accept: application/json"

# Ou avec plus de filtres
curl -v "http://localhost:3000/v1/pois?bbox=2.25,48.81,2.42,48.90&categories=restaurant&limit=50" \
  -H "Accept: application/json"
```

#### Ce qu'il faut vérifier

1. **Première requête (Cache MISS)**
   ```
   HTTP/1.1 200 OK
   X-Cache: MISS
   Content-Type: application/json
   ```
   - Temps de réponse cible: **~130ms** (au lieu de 155ms avant)
   - Vérifier que les POIs ont des photos enrichies
   - Vérifier que `mentions_count` et `mentions_sample` sont présents

2. **Deuxième requête identique (Cache HIT)**
   ```
   HTTP/1.1 200 OK
   X-Cache: HIT
   Content-Type: application/json
   ```
   - Temps de réponse cible: **~2-5ms** 🚀
   - Même contenu que la première requête

3. **Troisième requête après 5 minutes (Cache expiré)**
   - Devrait retourner `X-Cache: MISS` à nouveau

---

### Test 2: GET /v1/pois/:slug (Détail POI)

#### Requête de test
```bash
# Remplacer {slug} par un vrai slug de ta DB
curl -v "http://localhost:3000/v1/pois/restaurant-example?lang=fr" \
  -H "Accept: application/json"
```

#### Ce qu'il faut vérifier

1. **Cache MISS** (première requête)
   - `X-Cache: MISS`
   - Temps de réponse: **< 100ms**
   - POI avec toutes les photos enrichies

2. **Cache HIT** (requêtes suivantes)
   - `X-Cache: HIT`
   - Temps de réponse: **~2-5ms**

---

### Test 3: GET /v1/pois/facets (Facettes)

#### Requête de test
```bash
curl -v "http://localhost:3000/v1/pois/facets?bbox=2.25,48.81,2.42,48.90" \
  -H "Accept: application/json"
```

#### Ce qu'il faut vérifier
- Temps de réponse stable
- Facettes correctes (categories, price_levels, etc.)

---

## 📊 Métriques de succès

### Avant Phase 1 (baseline)
| Endpoint | Temps moyen | Queries DB |
|----------|-------------|------------|
| GET /v1/pois | **155ms** | 3 (RPC + photos + variants) |
| GET /v1/pois/:slug | **~100ms** | 3 |

### Après Phase 1 (objectif)
| Endpoint | Cache MISS | Cache HIT | Gain |
|----------|-----------|-----------|------|
| GET /v1/pois | **130ms** | **2-5ms** | **-16% / -98%** |
| GET /v1/pois/:slug | **~80ms** | **2-5ms** | **-20% / -98%** |

### Avec 90% de cache hit ratio (réaliste en production)
- **Temps moyen: 20-30ms** (au lieu de 155ms)
- **Réduction: 80-85%** 🎯

---

## 🔍 Validation approfondie

### 1. Vérifier les indexes SQL
```sql
-- Dans Supabase SQL Editor
SELECT
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('poi_photos', 'poi_photo_variants')
ORDER BY tablename, indexname;
```

**Attendu:** 4 nouveaux indexes
- `poi_photos_poi_id_status_idx`
- `poi_photos_poi_sort_idx`
- `poi_photo_variants_photo_id_idx`
- `poi_photo_variants_photo_variant_idx`

---

### 2. Tester l'efficacité du JOIN

Comparer l'ancien vs nouveau comportement:

**Ancien (2 queries séquentielles):**
```
Query 1: SELECT * FROM poi_photos WHERE poi_id IN (...)  → 15ms
Query 2: SELECT * FROM poi_photo_variants WHERE photo_id IN (...)  → 10ms
Total: 25ms
```

**Nouveau (1 query avec JOIN):**
```
Query 1: SELECT pp.*, ppv.* FROM poi_photos pp JOIN poi_photo_variants ppv  → 10-15ms
Total: 10-15ms (gain: 40-60%)
```

---

### 3. Monitoring du cache

Créer un script de monitoring simple:

```bash
#!/bin/bash
# test_cache_ratio.sh

echo "Testing cache hit ratio..."
echo "=========================="

for i in {1..10}; do
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}|%{header_json}" \
    "http://localhost:3000/v1/pois?bbox=2.25,48.81,2.42,48.90")

  echo "Request $i: $RESPONSE"
  sleep 0.5
done
```

**Résultat attendu:**
- 1ère requête: MISS + ~130ms
- Requêtes 2-10: HIT + ~2-5ms

---

## 🚨 Problèmes potentiels

### Cache ne fonctionne pas (toujours MISS)
**Diagnostic:**
```javascript
// Vérifier dans routes/v1/pois.js
console.log('Cache key:', cacheKey);
console.log('Cache size:', poisCache.size);
console.log('Cache has key:', poisCache.has(cacheKey));
```

**Causes possibles:**
- Paramètres pas dans le même ordre (résolu par `getCacheKey()`)
- TTL trop court (actuellement 5 minutes)
- Cache pas initialisé

---

### Temps toujours lent malgré cache HIT
**Diagnostic:**
- Vérifier que `X-Cache: HIT` est bien présent
- Vérifier les logs serveur pour latence réseau
- Tester en local vs déployé

---

### Photos manquantes ou incorrectes
**Diagnostic:**
```sql
-- Vérifier les données de test
SELECT
  poi_id,
  COUNT(*) as photo_count,
  COUNT(DISTINCT variant_key) as variant_count
FROM poi_photos pp
JOIN poi_photo_variants ppv ON ppv.photo_id = pp.id
WHERE pp.status = 'active'
  AND ppv.variant_key IN ('card_sq@1x', 'card_sq@2x')
GROUP BY poi_id
LIMIT 10;
```

---

## ✅ Checklist finale

- [ ] Indexes SQL déployés dans Supabase
- [ ] API redémarrée
- [ ] Test 1: Cache MISS = ~130ms
- [ ] Test 2: Cache HIT = ~2-5ms
- [ ] Test 3: Photos enrichies présentes
- [ ] Test 4: Mentions présentes (count + sample)
- [ ] Test 5: Headers `X-Cache` corrects
- [ ] Test 6: Pas d'erreurs dans les logs
- [ ] Monitoring: Ratio cache HIT > 80% en production

---

## 🎯 Prochaines étapes (si succès)

Si Phase 1 est un succès, on peut envisager:

1. **Phase 2:** Optimisations avancées
   - Cache partagé (Redis) pour multi-instances
   - Compression gzip/brotli
   - CDN pour responses statiques

2. **Phase 3:** Monitoring production
   - Prometheus metrics
   - Grafana dashboard
   - Alertes si temps > 100ms

3. **Migration Supabase Pro** (si trafic élevé)
   - RPC 30-50ms plus rapide
   - Connection pooling dédié
   - Temps moyen < 15ms possible
