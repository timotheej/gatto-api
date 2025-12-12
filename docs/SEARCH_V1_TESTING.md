# Search V1 - Testing Guide

Guide de test complet pour valider le système de recherche V1.

## Prérequis

1. ✅ Migrations DB exécutées (migrations/search_v1/001, 002a, 002b, 005, 006a + docs/sql/list_pois_rpc.sql)
2. ✅ Serveur API démarré (`npm start`)
3. ✅ Variable d'environnement `API_KEY_PUBLIC` configurée

## Tests Manuels

### 1. Test Autocomplete

#### Test 1.1 : Recherche de type (italien)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=ital&city=paris&lang=fr&limit=10"
```

**Résultat attendu** :
- `italian_restaurant` dans les suggestions (type)
- POIs avec "Ital" dans le nom
- Scores de relevance décroissants

#### Test 1.2 : Recherche de nom (Comptoir)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=comptoir&city=paris&lang=fr&limit=10"
```

**Résultat attendu** :
- POIs avec "Comptoir" dans le nom
- Matching fuzzy (tolère les typos)

#### Test 1.3 : Parent category (restaurant)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=restaurant&city=paris&lang=fr&limit=10"
```

**Résultat attendu** :
- `parent:restaurant` dans les suggestions (relevance 0.95)
- Types de restaurants (italian_restaurant, french_restaurant, etc.)

#### Test 1.4 : Multi-word (restaurant italien)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=restaurant%20italien&city=paris&lang=fr&limit=10"
```

**Résultat attendu** :
- `italian_restaurant` en premier (relevance 0.98)
- Pas de faux positifs (uniquement restaurants italiens)

---

### 2. Test Search (list_pois avec q)

#### Test 2.1 : Type search (italien)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=italien&city=paris&lang=fr&limit=20"
```

**Résultat attendu** :
- Liste de POIs de type `italian_restaurant`
- Filtres applicables (prix, quartier, etc.)
- Cache MISS la première fois, HIT la deuxième

#### Test 2.2 : Name search (Comptoir)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=Comptoir&city=paris&lang=fr&limit=20&sort=relevance"
```

**Résultat attendu** :
- POIs avec "Comptoir" dans le nom
- Chaque POI a un champ `name_relevance_score`
- Résultats triés par relevance (score décroissant)

#### Test 2.3 : Name search avec typo
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=comptoar&city=paris&lang=fr&limit=20&sort=relevance"
```

**Résultat attendu** :
- Trouve quand même "Comptoir" (fuzzy matching)
- Threshold adaptatif selon la longueur de la query

#### Test 2.4 : Backward compatibility (sans q)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?city=paris&type_keys=italian_restaurant&lang=fr&limit=20"
```

**Résultat attendu** :
- Fonctionne exactement comme avant
- Pas de régression

#### Test 2.5 : Search + filtres combinés
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=italien&city=paris&district_slug=11e-arrondissement&price_min=2&lang=fr&limit=20"
```

**Résultat attendu** :
- Restaurants italiens dans le 11e
- Prix >= 2
- Tous les filtres s'appliquent correctement

---

### 3. Test Facets avec Search

#### Test 3.1 : Facets pour type search
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois/facets?q=italien&city=paris&lang=fr"
```

**Résultat attendu** :
- Facettes contextuelles pour restaurants italiens
- Quartiers où il y a des restaurants italiens
- Prix disponibles, etc.

---

### 4. Test Cache Performance

#### Test 4.1 : Cache HIT sur autocomplete
```bash
# Première requête (MISS)
time curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=italien&city=paris&lang=fr" \
  -o /dev/null -s -w "%{http_code} - %{time_total}s\n"

# Deuxième requête immédiate (HIT)
time curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=italien&city=paris&lang=fr" \
  -o /dev/null -s -w "%{http_code} - %{time_total}s\n"
```

**Résultat attendu** :
- Première requête : ~50-100ms (cache MISS)
- Deuxième requête : <10ms (cache HIT)
- Header `X-Cache: HIT` dans la réponse

#### Test 4.2 : Cache HIT sur search
```bash
# MISS
time curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=italien&city=paris&limit=20" \
  -o /dev/null -s -w "%{http_code} - %{time_total}s\n"

# HIT
time curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=italien&city=paris&limit=20" \
  -o /dev/null -s -w "%{http_code} - %{time_total}s\n"
```

**Résultat attendu** :
- Cache HIT significativement plus rapide
- TTL: 5 min pour /pois, 1 min pour /autocomplete

---

### 5. Test Monitoring

#### Test 5.1 : Métriques disponibles
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/metrics"
```

**Résultat attendu** :
```json
{
  "success": true,
  "data": {
    "autocomplete": {
      "total_requests": 10,
      "cache_hit_rate": "60.00%",
      "error_rate": "0.00%",
      "avg_response_time_ms": 45,
      "popular_queries": [
        { "query": "italien", "count": 5 },
        { "query": "comptoir", "count": 3 }
      ]
    },
    "search": {
      "total_requests": 5,
      "cache_hit_rate": "40.00%",
      "error_rate": "0.00%",
      "avg_response_time_ms": 120,
      "name_searches": 2,
      "type_searches": 3,
      "popular_queries": [...]
    }
  }
}
```

---

### 6. Test Error Handling

#### Test 6.1 : Query trop courte (validation)
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/autocomplete?q=&city=paris"
```

**Résultat attendu** :
- HTTP 400
- Message d'erreur Zod clair

#### Test 6.2 : Sort relevance sans query
```bash
curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?city=paris&sort=relevance&limit=20"
```

**Résultat attendu** :
- HTTP 400
- Message: "Query parameter 'q' is required when sort='relevance'"

#### Test 6.3 : Rate limiting
```bash
for i in {1..70}; do
  curl -H "x-api-key: $API_KEY_PUBLIC" \
    "http://localhost:3100/v1/autocomplete?q=test$i&city=paris" \
    -s -o /dev/null -w "%{http_code}\n"
done
```

**Résultat attendu** :
- Premières 60 requêtes : HTTP 200
- Après 60 : HTTP 429 (Too Many Requests)
- Message avec temps d'attente (retry-after)

---

## Tests de Performance

### 1. Autocomplete Response Time
```bash
# Mesurer 100 requêtes variées
for i in {1..100}; do
  time curl -H "x-api-key: $API_KEY_PUBLIC" \
    "http://localhost:3100/v1/autocomplete?q=test$i&city=paris" \
    -s -o /dev/null -w "%{time_total}\n"
done | awk '{ sum += $1; n++ } END { if (n > 0) print "Avg: " sum / n " seconds"; }'
```

**Target** : < 100ms moyenne (incluant cache hits/misses)

### 2. Search Response Time
```bash
# Mesurer temps de réponse avec name search
time curl -H "x-api-key: $API_KEY_PUBLIC" \
  "http://localhost:3100/v1/pois?q=comptoir&city=paris&sort=relevance&limit=20" \
  -s -o /dev/null -w "Total: %{time_total}s\n"
```

**Target** : < 200ms pour name search (cache MISS)

---

## Checklist de Validation

### Database
- [ ] Extensions pg_trgm et unaccent installées
- [ ] Colonnes name_normalized créées sur table poi
- [ ] Index GIN trigram créés (3 index)
- [ ] Fonction normalize_for_search() disponible
- [ ] RPC autocomplete_search() créé
- [ ] RPC list_pois() mis à jour avec p_name_search

### API Endpoints
- [ ] GET /v1/autocomplete fonctionne
- [ ] GET /v1/pois accepte paramètre q
- [ ] GET /v1/pois retourne name_relevance_score si q fourni
- [ ] GET /v1/pois/facets supporte q
- [ ] GET /v1/metrics retourne les statistiques

### Features
- [ ] Autocomplete retourne types + POIs
- [ ] Parent categories détectées ("restaurant")
- [ ] Multi-word queries fonctionnent ("restaurant italien")
- [ ] Fuzzy matching tolère les typos
- [ ] Type detection fonctionne ("italien" → italian_restaurant)
- [ ] Name search avec sort=relevance fonctionne
- [ ] Backward compatibility préservée (sans q)

### Performance
- [ ] Autocomplete < 50ms (cache HIT)
- [ ] Autocomplete < 100ms (cache MISS)
- [ ] Search name < 200ms
- [ ] Cache working (X-Cache headers)
- [ ] Rate limiting actif (60 req/min)

### Monitoring
- [ ] Métriques collectées (autocomplete + search)
- [ ] Cache hit rate visible
- [ ] Popular queries trackées
- [ ] Error rate < 1%

---

## Troubleshooting

### Autocomplete retourne []
1. Vérifier que les migrations sont appliquées
2. Vérifier que poi_types a detection_keywords_fr/en
3. Tester directement le RPC : `SELECT * FROM autocomplete_search('italien', 'paris', 'fr', 10);`

### Name search ne trouve rien
1. Vérifier que name_normalized est peuplé : `SELECT name, name_normalized FROM poi LIMIT 5;`
2. Tester la similarité : `SELECT similarity('comptoir', 'Le Comptoir');` (doit être > 0.3)
3. Vérifier les index : `SELECT indexname FROM pg_indexes WHERE tablename = 'poi' AND indexname LIKE '%trgm%';`

### Cache ne fonctionne pas
1. Vérifier les headers de réponse (X-Cache)
2. Les paramètres doivent être identiques (ordre importe pas, mais valeurs oui)
3. Vérifier TTL : 1 min pour autocomplete, 5 min pour pois

### Performances lentes
1. Vérifier que les index sont utilisés : `EXPLAIN ANALYZE SELECT * FROM autocomplete_search(...)`
2. Vérifier le cache hit rate dans /v1/metrics
3. Augmenter la taille du cache LRU si besoin

---

**Date de création** : 2025-12-12
**Version** : Search V1
**Statut** : Ready for testing
