# API POI - Documentation complète

## Vue d'ensemble

L'API POI permet de récupérer des informations sur les points d'intérêt (restaurants, bars, etc.) avec des fonctionnalités avancées de filtrage, tri et pagination.

## Endpoints

### 1. Liste paginée des POIs

**Endpoint:** `GET /v1/poi`

Récupère une liste paginée de POIs avec filtres et tri.

#### Paramètres de requête

| Paramètre | Type | Défaut | Description |
|-----------|------|--------|-------------|
| `view` | string | `'card'` | Format de retour : `'card'` ou `'detail'` |
| `segment` | string | `'gatto'` | Segment de scoring : `'gatto'` \| `'digital'` \| `'awarded'` \| `'fresh'` |
| `category` | string | - | Catégorie unique ou multiples séparées par virgule (AND) |
| `subcategory` | string | - | Sous-catégories multiples séparées par virgule (AND) |
| `neighbourhood_slug` | string | - | Slug du quartier (ex: `'haut-marais'`) |
| `district_slug` | string | - | Slug de l'arrondissement (ex: `'10e-arrondissement'`) |
| `tags` | string | - | Tags avec logique AND (ex: `'trendy,modern'`) |
| `tags_any` | string | - | Tags avec logique OR (ex: `'terrace,michelin'`) |
| `price` | integer | - | Niveau de prix : `1` (€) \| `2` (€€) \| `3` (€€€) \| `4` (€€€€) |
| `awarded` | boolean | - | Filtre sur les lieux primés (`true`/`false`) |
| `fresh` | boolean | - | Filtre sur les nouveautés (`true`/`false`) |
| `sort` | string | `'gatto'` | Tri : `'gatto'` \| `'digital'` \| `'price_desc'` \| `'price_asc'` \| `'mentions'` \| `'rating'` |
| `city` | string | `'paris'` | Ville |
| `limit` | integer | `24` | Nombre d'items (max 50) |
| `cursor` | string | - | Curseur de pagination (base64) |
| `fields` | string | - | Champs à inclure (ex: `'scores,rating,tags'`) |

#### Exemples d'usage

```javascript
// Bars de prix moyen primés, triés par mentions
GET /v1/poi?category=bar&price=2&awarded=true&sort=mentions&limit=10

// Restaurants français récents, triés par prix décroissant
GET /v1/poi?category=restaurant&subcategory=french_restaurant&fresh=true&sort=price_desc

// Bars ET restaurants, triés par note
GET /v1/poi?category=restaurant,bar&sort=rating&limit=5

// Lieux avec terrasse OU étoilé Michelin dans le Marais
GET /v1/poi?neighbourhood_slug=marais&tags_any=terrace,michelin

// Lieux tendance ET moderne dans le 10e
GET /v1/poi?district_slug=10e-arrondissement&tags=trendy,modern
```

#### Structure de réponse

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "slug": "nom-du-lieu",
        "name": "Nom du lieu",
        "category": "restaurant",
        "district": "Paris 10e Arrondissement",
        "neighbourhood": "Quartier République",
        "photo": {
          "variants": [
            {
              "variant_key": "card_sq@1x",
              "format": "avif",
              "url": "https://cdn.gatto.city/...",
              "width": 256,
              "height": 256
            }
          ],
          "dominant_color": "#hex",
          "blurhash": "string"
        },
        "score": 75.5,
        "scores": {
          "gatto": 75.5,
          "digital": 65.2,
          "awards_bonus": 8,
          "freshness_bonus": 2
        },
        "rating": {
          "google": 4.3,
          "reviews_count": 1248
        },
        "mentions_count": 12,
        "mentions_sample": [
          {
            "domain": "timeout.fr",
            "favicon": "https://www.google.com/s2/favicons?domain=timeout.fr&sz=64",
            "url": "https://...",
            "title": "Titre de l'article"
          }
        ],
        "tags_flat": ["modern", "trendy", "terrace"]
      }
    ],
    "next_cursor": "eyJzY29yZSI6NzUsImlkIjoidXVpZCJ9",
    "previous_cursor": null
  }
}
```

#### Vue détaillée (`view=detail`)

Avec `view=detail`, les items incluent des champs supplémentaires :

```json
{
  "summary": "Résumé IA du lieu",
  "coords": { "lat": 48.8566, "lng": 2.3522 },
  "price_level": "PRICE_LEVEL_MODERATE",
  "opening_hours": { /* horaires */ },
  "photos": {
    "primary": { /* photo principale */ },
    "gallery": [ /* jusqu'à 5 photos */ ]
  }
}
```

### 2. Détail d'un POI

**Endpoint:** `GET /v1/poi/:slug`

Récupère les détails complets d'un POI.

#### Paramètres

| Paramètre | Type | Description |
|-----------|------|-------------|
| `slug` | string | Slug du POI (dans l'URL) |

Les headers `Accept-Language` sont pris en compte pour la langue (`fr`/`en`).

#### Structure de réponse

```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "slug": "nom-du-lieu",
    "name": "Nom du lieu",
    "category": "restaurant",
    "city": "Paris",
    "district": "Paris 10e Arrondissement",
    "neighbourhood": "Quartier République",
    "coords": { "lat": 48.8566, "lng": 2.3522 },
    "price_level": "PRICE_LEVEL_MODERATE",
    "tags_keys": { /* structure des tags */ },
    "tags": { /* tags enrichis avec labels */ },
    "summary": "Résumé détaillé du lieu",
    "opening_hours": { /* horaires détaillés */ },
    "google_place_id": "ChIJ...",
    "address": "123 Rue Example, Paris",
    "website": "https://example.com",
    "phone": "+33123456789",
    "photos": {
      "primary": {
        "variants": [ /* variantes haute résolution */ ],
        "width": 800,
        "height": 600,
        "dominant_color": "#hex",
        "blurhash": "string",
        "gallery": { /* version galerie */ }
      },
      "gallery": [
        { /* photos additionnelles */ }
      ]
    },
    "scores": {
      "gatto": 75.5,
      "digital": 65.2,
      "awards_bonus": 8,
      "freshness_bonus": 2,
      "calculated_at": "2024-01-15T10:30:00Z"
    },
    "rating": {
      "google": 4.3,
      "reviews_count": 1248
    },
    "mentions_count": 12,
    "mentions_sample": [
      {
        "domain": "timeout.fr",
        "favicon": "https://...",
        "title": "Titre",
        "excerpt": "Extrait de l'article",
        "url": "https://..."
      }
    ],
    "breadcrumb": [
      { "label": "Accueil", "href": "/" },
      { "label": "Paris", "href": "/paris" },
      { "label": "10e Arrondissement", "href": "/paris/10e-arrondissement" },
      { "label": "République", "href": "/paris/10e-arrondissement/republique" }
    ]
  }
}
```

## Filtrage avancé

### Catégories

```javascript
// Catégorie unique
GET /v1/poi?category=restaurant

// Catégories multiples (AND)
GET /v1/poi?category=restaurant,bar,café
```

**Catégories disponibles :** `restaurant`, `bar`, `café`, `boulangerie`, `patisserie`, `hotel`, etc.

### Sous-catégories

```javascript
// Restaurants français uniquement
GET /v1/poi?category=restaurant&subcategory=french_restaurant

// Restaurants français ET italiens
GET /v1/poi?category=restaurant&subcategory=french_restaurant,italian_restaurant
```

### Tags

```javascript
// Lieux avec terrasse ET moderne (AND)
GET /v1/poi?tags=terrace,modern

// Lieux avec terrasse OU Michelin (OR)
GET /v1/poi?tags_any=terrace,michelin

// Combinaison : terrasse ET (Michelin OU trendy)
GET /v1/poi?tags=terrace&tags_any=michelin,trendy
```

### Localisation

```javascript
// Par quartier
GET /v1/poi?neighbourhood_slug=saint-germain-des-pres

// Par arrondissement  
GET /v1/poi?district_slug=6e-arrondissement

// Combinaison
GET /v1/poi?district_slug=10e-arrondissement&neighbourhood_slug=republique
```

## Tri et scoring

### Options de tri

| `sort` | Description |
|--------|-------------|
| `gatto` | Score Gatto global (défaut) |
| `digital` | Score présence digitale |
| `price_desc` | Prix décroissant (€€€€ → €) |
| `price_asc` | Prix croissant (€ → €€€€) |
| `mentions` | Nombre de mentions presse |
| `rating` | Note Google |

### Segments de scoring

| `segment` | Description |
|-----------|-------------|
| `gatto` | Score global Gatto (défaut) |
| `digital` | Lieux avec forte présence digitale |
| `awarded` | Lieux primés/reconnus |
| `fresh` | Nouveautés et découvertes |

```javascript
// Top des lieux primés
GET /v1/poi?segment=awarded&sort=gatto

// Nouveautés triées par mentions
GET /v1/poi?segment=fresh&sort=mentions
```

## Pagination

La pagination utilise un système de curseur (keyset pagination) pour des performances optimales :

```javascript
// Première page
GET /v1/poi?limit=20

// Page suivante (utiliser next_cursor de la réponse précédente)
GET /v1/poi?limit=20&cursor=eyJzY29yZSI6NzUsImlkIjoidXVpZCJ9
```

## Optimisation des champs

Utilisez le paramètre `fields` pour ne récupérer que les données nécessaires :

```javascript
// Seulement les scores
GET /v1/poi?fields=scores

// Scores et tags
GET /v1/poi?fields=scores,tags_flat

// Tous les champs (défaut)
GET /v1/poi
```

## Gestion des images

### Formats supportés
- **AVIF** : Format moderne, compression optimale
- **WebP** : Bon compromis compatibilité/performance  
- **JPEG** : Compatibilité maximale

### Variantes disponibles

#### Vue carte
- `card_sq@1x` : 256×256px pour écrans standard
- `card_sq@2x` : 512×512px pour écrans haute densité

#### Vue détail
- `detail@1x` : Format détail standard
- `detail@2x` : Format détail haute résolution
- `thumb_small@1x` : Vignettes pour galerie
- `gallery@1x` : Format galerie

### Utilisation recommandée

```html
<picture>
  <source srcset="image@1x.avif 1x, image@2x.avif 2x" type="image/avif">
  <source srcset="image@1x.webp 1x, image@2x.webp 2x" type="image/webp">
  <img src="image@1x.jpg" srcset="image@1x.jpg 1x, image@2x.jpg 2x" alt="...">
</picture>
```

## Codes d'erreur

| Code | Description |
|------|-------------|
| `200` | Succès |
| `404` | POI non trouvé (pour `/poi/:slug`) |
| `500` | Erreur serveur |

## Limites et performances

- **Limite par page :** 50 items maximum
- **Cache :** 5 minutes (Cache-Control: public, max-age=300)
- **Timeout :** Les requêtes complexes peuvent prendre jusqu'à 2-3 secondes

## Exemples d'implémentation

### React/Next.js

```javascript
// Hook personnalisé pour la liste POI
function usePOIList(filters = {}) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  
  useEffect(() => {
    const params = new URLSearchParams();
    Object.entries(filters).forEach(([key, value]) => {
      if (value) params.append(key, value);
    });
    
    fetch(`/api/v1/poi?${params}`)
      .then(res => res.json())
      .then(setData)
      .finally(() => setLoading(false));
  }, [filters]);
  
  return { data, loading };
}

// Utilisation
function POIList() {
  const { data, loading } = usePOIList({
    category: 'restaurant',
    neighbourhood_slug: 'marais',
    awarded: true,
    sort: 'gatto',
    limit: 12
  });
  
  if (loading) return <div>Chargement...</div>;
  
  return (
    <div className="grid grid-cols-3 gap-4">
      {data?.data?.items?.map(poi => (
        <POICard key={poi.id} poi={poi} />
      ))}
    </div>
  );
}
```

### Filtres dynamiques

```javascript
function POIFilters({ onFiltersChange }) {
  const [filters, setFilters] = useState({});
  
  const updateFilter = (key, value) => {
    const newFilters = { ...filters, [key]: value };
    setFilters(newFilters);
    onFiltersChange(newFilters);
  };
  
  return (
    <div>
      <select onChange={(e) => updateFilter('category', e.target.value)}>
        <option value="">Toutes catégories</option>
        <option value="restaurant">Restaurants</option>
        <option value="bar">Bars</option>
      </select>
      
      <select onChange={(e) => updateFilter('price', e.target.value)}>
        <option value="">Tous prix</option>
        <option value="1">€</option>
        <option value="2">€€</option>
        <option value="3">€€€</option>
        <option value="4">€€€€</option>
      </select>
      
      <select onChange={(e) => updateFilter('sort', e.target.value)}>
        <option value="gatto">Score Gatto</option>
        <option value="rating">Note Google</option>
        <option value="mentions">Mentions presse</option>
      </select>
    </div>
  );
}
```