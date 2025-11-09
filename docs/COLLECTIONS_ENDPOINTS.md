# Collections Endpoints

Documentation complète des endpoints `/v1/collections` et `/v1/collections/:slug`.

## Table des matières

- [Vue d'ensemble](#vue-densemble)
- [GET /v1/collections](#get-v1collections)
- [GET /v1/collections/:slug](#get-v1collectionsslug)
- [Structures de données](#structures-de-données)
- [Cache et performance](#cache-et-performance)
- [Exemples d'utilisation](#exemples-dutilisation)

---

## Vue d'ensemble

Les endpoints collections permettent de :
- **Lister toutes les collections** d'une ville avec pagination
- **Récupérer les POIs** d'une collection spécifique avec toutes leurs données

### Fonctionnalités

- ✅ Support multilingue (FR/EN) avec fallback automatique
- ✅ Pagination complète sur tous les endpoints
- ✅ Cache LRU (5 minutes TTL)
- ✅ Photos avec variants optimisés (@1x, @2x, avif, webp)
- ✅ Slug matching intelligent (accepte slug_fr, slug_en ou slug legacy)
- ✅ Validation Zod stricte des paramètres

---

## GET /v1/collections

Liste toutes les collections pour une ville donnée.

### Endpoint

```
GET /v1/collections
```

### Paramètres de requête

| Paramètre | Type | Requis | Défaut | Description |
|-----------|------|--------|--------|-------------|
| `city` | string | ✅ Oui | - | Slug de la ville (ex: `paris`) |
| `lang` | string | Non | `fr` | Langue (`fr` ou `en`) |
| `limit` | integer | Non | `20` | Nombre de résultats par page (max: 100) |
| `page` | integer | Non | `1` | Numéro de page |

### Exemple de requête

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections?city=paris&lang=fr&limit=10&page=1"
```

### Exemple de réponse

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "08b4e2a9-6dab-4c78-94c8-aaf579cda8a0",
        "slug": "adresses-cocooning-pour-l-automne",
        "slug_fr": "adresses-cocooning-pour-l-automne",
        "slug_en": "cozy-spots-for-autumn",
        "title": "Adresses cocooning pour l'automne",
        "title_fr": "Adresses cocooning pour l'automne",
        "title_en": "Cozy Spots for Autumn",
        "city_slug": "paris",
        "is_dynamic": true,
        "rules_json": {
          "p_sort": "gatto",
          "p_tags_all": ["cozy"],
          "p_tags_any": ["intimate_setting", "warm_hospitality"]
        },
        "theme_type": "seasonal",
        "season_window": "Nov–Feb",
        "cover_photo": {
          "variants": [
            {
              "variant_key": "card_sq@1x",
              "format": "avif",
              "url": "https://cdn.gatto.city/poi/.../card_sq@1x.avif",
              "width": 256,
              "height": 256
            },
            {
              "variant_key": "card_sq@2x",
              "format": "webp",
              "url": "https://cdn.gatto.city/poi/.../card_sq@2x.webp",
              "width": 512,
              "height": 512
            }
          ],
          "dominant_color": "#32382d",
          "blurhash": "L6PZfSi_.AyE_3t7t7R**0o#DgR4"
        },
        "created_at": "2025-11-09T12:38:44.729306+00:00",
        "updated_at": "2025-11-09T12:38:44.729306+00:00"
      }
    ],
    "pagination": {
      "total": 3,
      "per_page": 10,
      "current_page": 1,
      "total_pages": 1,
      "has_next": false,
      "has_prev": false
    }
  },
  "timestamp": "2025-11-09T13:00:00.000Z"
}
```

### Codes de réponse

| Code | Description |
|------|-------------|
| `200` | Succès - Collections retournées |
| `400` | Paramètres invalides (validation Zod) |
| `401` | API key manquante ou invalide |
| `500` | Erreur serveur |

---

## GET /v1/collections/:slug

Récupère une collection spécifique avec tous ses POIs.

### Endpoint

```
GET /v1/collections/:slug
```

### Paramètres de chemin

| Paramètre | Type | Description |
|-----------|------|-------------|
| `slug` | string | Slug de la collection (accepte `slug_fr`, `slug_en` ou `slug`) |

### Paramètres de requête

| Paramètre | Type | Requis | Défaut | Description |
|-----------|------|--------|--------|-------------|
| `lang` | string | Non | `fr` | Langue (`fr` ou `en`) |
| `limit` | integer | Non | `50` | Nombre de POIs par page (max: 100) |
| `page` | integer | Non | `1` | Numéro de page |

### Exemple de requête

```bash
# Avec slug français
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/adresses-cocooning-pour-l-automne?limit=10"

# Avec slug anglais
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/cozy-spots-for-autumn?lang=en&limit=10"
```

### Exemple de réponse

```json
{
  "success": true,
  "data": {
    "collection": {
      "id": "08b4e2a9-6dab-4c78-94c8-aaf579cda8a0",
      "slug": "adresses-cocooning-pour-l-automne",
      "slug_fr": "adresses-cocooning-pour-l-automne",
      "slug_en": "cozy-spots-for-autumn",
      "title": "Adresses cocooning pour l'automne",
      "title_fr": "Adresses cocooning pour l'automne",
      "title_en": "Cozy Spots for Autumn",
      "city_slug": "paris",
      "is_dynamic": true,
      "rules_json": { ... },
      "theme_type": "seasonal",
      "season_window": "Nov–Feb",
      "cover_photo": { ... },
      "created_at": "2025-11-09T12:38:44.729306+00:00",
      "updated_at": "2025-11-09T12:38:44.729306+00:00"
    },
    "pois": [
      {
        "id": "9ad38c70-e38e-41b3-a16e-fb466a123cbe",
        "slug": "chez-janou",
        "name": "Chez Janou",
        "primary_type": "french_restaurant",
        "subcategories": ["french_restaurant", "restaurant"],
        "district": "paris-3e-arrondissement",
        "neighbourhood": "quartier-des-archives",
        "coords": {
          "lat": 48.8567159,
          "lng": 2.3671983
        },
        "photo": {
          "variants": [ ... ],
          "dominant_color": "#32382d",
          "blurhash": "L6PZfSi_.AyE_3t7t7R**0o#DgR4"
        },
        "price_level": "PRICE_LEVEL_MODERATE",
        "score": 74,
        "scores": {
          "gatto": 74,
          "digital": 55,
          "awards_bonus": 15,
          "freshness_bonus": 4
        },
        "rating": {
          "google": 4.3,
          "reviews_count": 6749
        },
        "mentions_count": 5,
        "mentions_sample": [
          {
            "domain": "pariszigzag.fr",
            "favicon": "https://www.google.com/s2/favicons?domain=pariszigzag.fr&sz=64",
            "url": "https://www.pariszigzag.fr/...",
            "title": "Chez Janou, le joli bistrot provençal..."
          }
        ],
        "tags_flat": ["cozy", "bistro_style", "traditional"],
        "collection_position": 1,
        "collection_reason": null
      }
    ],
    "pagination": {
      "total": 20,
      "per_page": 50,
      "current_page": 1,
      "total_pages": 1,
      "has_next": false,
      "has_prev": false
    }
  },
  "timestamp": "2025-11-09T13:00:00.000Z"
}
```

### Codes de réponse

| Code | Description |
|------|-------------|
| `200` | Succès - Collection et POIs retournés |
| `400` | Paramètres invalides (validation Zod) |
| `401` | API key manquante ou invalide |
| `404` | Collection non trouvée |
| `500` | Erreur serveur |

---

## Structures de données

### Collection

| Champ | Type | Description |
|-------|------|-------------|
| `id` | UUID | Identifiant unique de la collection |
| `slug` | string | Slug actif selon la langue (`slug_fr` ou `slug_en`) |
| `slug_fr` | string | Slug français |
| `slug_en` | string | Slug anglais |
| `title` | string | Titre actif selon la langue |
| `title_fr` | string | Titre français |
| `title_en` | string | Titre anglais |
| `city_slug` | string | Slug de la ville |
| `is_dynamic` | boolean | Collection dynamique (basée sur rules_json) ou statique |
| `rules_json` | object | Règles de filtrage pour collections dynamiques |
| `theme_type` | string | Type de thème (`seasonal`, `evergreen`, etc.) |
| `season_window` | string | Fenêtre saisonnière (ex: "Nov–Feb") |
| `cover_photo` | object | Photo de couverture avec variants |
| `created_at` | timestamp | Date de création |
| `updated_at` | timestamp | Date de dernière mise à jour |

### POI (dans collection)

Même structure que `/v1/pois` avec les champs additionnels :

| Champ | Type | Description |
|-------|------|-------------|
| `collection_position` | integer | Position du POI dans la collection |
| `collection_reason` | string | Raison de l'inclusion dans la collection (peut être null) |

### Photo Variants

Chaque photo contient des variants optimisés :

```json
{
  "variants": [
    {
      "variant_key": "card_sq@1x",
      "format": "avif",
      "url": "https://cdn.gatto.city/...",
      "width": 256,
      "height": 256
    },
    {
      "variant_key": "card_sq@1x",
      "format": "webp",
      "url": "https://cdn.gatto.city/...",
      "width": 256,
      "height": 256
    },
    {
      "variant_key": "card_sq@2x",
      "format": "avif",
      "url": "https://cdn.gatto.city/...",
      "width": 512,
      "height": 512
    },
    {
      "variant_key": "card_sq@2x",
      "format": "webp",
      "url": "https://cdn.gatto.city/...",
      "width": 512,
      "height": 512
    }
  ],
  "dominant_color": "#32382d",
  "blurhash": "L6PZfSi_.AyE_3t7t7R**0o#DgR4"
}
```

### Pagination

```json
{
  "total": 20,
  "per_page": 50,
  "current_page": 1,
  "total_pages": 1,
  "has_next": false,
  "has_prev": false
}
```

---

## Cache et performance

### Stratégie de cache

- **Type** : LRU Cache (Least Recently Used)
- **TTL** : 5 minutes (300 secondes)
- **Taille max** : 500 entrées
- **Clés** : Basées sur tous les paramètres de requête

### Headers de cache

Chaque réponse inclut :

```
X-Cache: HIT | MISS
Cache-Control: public, max-age=600
```

### Performance

- **Liste collections** : ~50-150ms (sans cache)
- **Collection + POIs** : ~100-300ms (sans cache)
- **Avec cache** : ~5-15ms

### Optimisations

1. **Photos** : JOIN optimisé pour récupérer photos + variants en 1 seule requête
2. **Scores/Ratings** : Utilisation de vues matérialisées (`latest_gatto_scores`, `latest_google_rating`)
3. **Mentions** : Agrégation SQL (évite le traitement en JavaScript)
4. **Index** : Index sur `city_slug`, `updated_at`, `position`

---

## Exemples d'utilisation

### 1. Lister les collections de Paris

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections?city=paris"
```

### 2. Lister avec pagination

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections?city=paris&limit=10&page=2"
```

### 3. Récupérer une collection avec ses POIs

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/adresses-cocooning-pour-l-automne"
```

### 4. Collection en anglais avec pagination

```bash
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/cozy-spots-for-autumn?lang=en&limit=10&page=1"
```

### 5. Naviguer entre les pages

```bash
# Page 1
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/meilleurs-brunchs-a-paris?page=1&limit=5"

# Page 2
curl -H "x-api-key: YOUR_API_KEY" \
  "http://localhost:3100/v1/collections/meilleurs-brunchs-a-paris?page=2&limit=5"
```

### 6. Exemple JavaScript/TypeScript

```typescript
const fetchCollections = async (city: string, page = 1) => {
  const response = await fetch(
    `https://api.gatto.city/v1/collections?city=${city}&page=${page}`,
    {
      headers: {
        'x-api-key': process.env.GATTO_API_KEY
      }
    }
  );

  if (!response.ok) {
    throw new Error('Failed to fetch collections');
  }

  return response.json();
};

const fetchCollectionPois = async (slug: string, lang = 'fr') => {
  const response = await fetch(
    `https://api.gatto.city/v1/collections/${slug}?lang=${lang}`,
    {
      headers: {
        'x-api-key': process.env.GATTO_API_KEY
      }
    }
  );

  if (!response.ok) {
    throw new Error('Collection not found');
  }

  return response.json();
};
```

---

## Gestion des erreurs

### Erreurs de validation

```json
{
  "success": false,
  "error": "Invalid query parameters",
  "details": [
    {
      "field": "city",
      "message": "Required",
      "code": "invalid_type"
    }
  ],
  "timestamp": "2025-11-09T13:00:00.000Z"
}
```

### Collection non trouvée

```json
{
  "success": false,
  "error": "Collection not found",
  "timestamp": "2025-11-09T13:00:00.000Z"
}
```

### API Key invalide

```json
{
  "success": false,
  "error": "Unauthorized - Invalid or missing API key",
  "timestamp": "2025-11-09T13:00:00.000Z"
}
```

---

## Base de données

### Fonctions RPC Supabase

Les endpoints utilisent deux fonctions RPC :

1. **`list_collections(p_city_slug, p_limit, p_page)`**
   - Liste les collections avec pagination
   - Retourne les photos de couverture enrichies

2. **`get_collection_pois(p_slug, p_limit, p_page)`**
   - Récupère une collection + ses POIs
   - Accepte slug_fr, slug_en ou slug
   - JOIN avec `collection_item` pour l'ordre

### Tables impliquées

- `collection` : Données des collections
- `collection_item` : Liaison collection ↔ POI avec position
- `poi` : Données des POIs
- `poi_photos` : Photos des POIs et collections
- `poi_photo_variants` : Variants optimisés des photos
- `latest_gatto_scores` : Scores Gatto (vue matérialisée)
- `latest_google_rating` : Ratings Google (vue matérialisée)
- `ai_mention` : Mentions AI

---

## Notes importantes

### Support multilingue

- Le paramètre `lang` affecte les champs `slug` et `title` retournés
- Les champs `slug_fr`, `slug_en`, `title_fr`, `title_en` sont **toujours** présents
- Fallback automatique : FR → EN → legacy → null

### Slug matching

L'endpoint `/v1/collections/:slug` accepte :
- `slug_fr` (ex: "adresses-cocooning-pour-l-automne")
- `slug_en` (ex: "cozy-spots-for-autumn")
- `slug` (legacy, si présent)

### Collections dynamiques vs statiques

- **Dynamiques** (`is_dynamic: true`) : POIs générés via `rules_json`
- **Statiques** (`is_dynamic: false`) : POIs définis manuellement via `collection_item`

Actuellement, toutes les collections utilisent `collection_item` pour un ordre précis.

---

## Changelog

### v1.0.0 - 2025-11-09

- ✅ Création des endpoints `/v1/collections` et `/v1/collections/:slug`
- ✅ Support multilingue (FR/EN)
- ✅ Pagination complète
- ✅ Cache LRU 5 minutes
- ✅ Photos avec variants optimisés
- ✅ Validation Zod stricte
- ✅ Documentation complète

---

## Support

Pour toute question ou bug :
- Créer une issue sur le repository
- Contacter l'équipe backend

**Date de création** : 2025-11-09
**Auteur** : Claude
**Version** : 1.0.0
