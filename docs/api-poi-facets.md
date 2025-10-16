# API Endpoint: GET /v1/poi/facets

## Description
Retourne les facettes disponibles pour les POI selon le contexte géographique et les filtres appliqués. Utilisé pour construire des interfaces de filtrage dynamiques.

## URL
```
GET /v1/poi/facets
```

## Paramètres de requête (Query Parameters)

| Paramètre | Type | Requis | Défaut | Description |
|-----------|------|--------|---------|-------------|
| `city` | string | Oui | `"paris"` | Slug de la ville active |
| `sort` | string | Oui | `"gatto"` | Aligné sur la liste (`gatto`, `price_desc`, `price_asc`, `mentions`, `rating`) |
| `category` | string | Non | - | Slug de catégorie (single-choice) |
| `subcategory` | string | Non | - | CSV de sous-catégories (logique OR) |
| `district_slug` | string | Non | - | CSV d'arrondissements (logique OR) |
| `neighbourhood_slug` | string | Non | - | CSV de quartiers (logique OR) |
| `tags` | string | Non | - | CSV de tags (logique AND) |
| `tags_any` | string | Non | - | CSV de tags (logique OR) |
| `awards` | string | Non | - | CSV de providers d'awards (logique OR) |
| `price_min` | number | Non | - | Borne min de prix (1 à 4, inclusif) |
| `price_max` | number | Non | - | Borne max de prix (1 à 4, inclusif) |
| `rating_min` | number | Non | - | Borne min de rating (0 à 5, inclusif) |
| `rating_max` | number | Non | - | Borne max de rating (0 à 5, inclusif) |
| `awarded` | boolean | Non | - | Ne conserve que les POI récompensés (`true`/`false`) |
| `fresh` | boolean | Non | - | Ne conserve que les POI “fresh” (`true`/`false`) |
| `lang` | string | Non | Auto-détecté | Langue (`"fr"` ou `"en"`) |

## Headers
- `Accept-Language`: Utilisé pour détecter la langue si `lang` non fourni (défaut: `fr`)

## Structure de réponse

### Succès (200)
```json
{
  "success": true,
  "data": {
    "context": {
      "city": "paris",
      "total_results": 312,
      "applied_filters": {
        "category": ["restaurant"],
        "price": { "min": 2, "max": 3 },
        "rating": { "min": 4, "max": 5 },
        "district_slug": ["10e-arrondissement","11e-arrondissement"],
        "sort": "rating"
      }
    },
    "facets": {
      "category": [
        {
          "count": 208,
          "value": "restaurant"
        },
        {
          "count": 54,
          "value": "bar"
        }
      ],
      "subcategories": [
        {
          "count": 72,
          "value": "french_restaurant"
        }
      ],
      "price": [
        {
          "count": 18,
          "value": "1",
          "label": "€"
        },
        {
          "count": 126,
          "value": "2",
          "label": "€€"
        },
        {
          "count": 93,
          "value": "3",
          "label": "€€€"
        }
      ],
      "price_levels": [
        { "value": "1", "label": "€" },
        { "value": "2", "label": "€€" },
        { "value": "3", "label": "€€€" },
        { "value": "4", "label": "€€€€" }
      ],
      "rating_range": {
        "min": 3.6,
        "max": 4.9
      },
      "tags": [
        {
          "count": 244,
          "label": "Voyage Culinaire",
          "value": "culinary_journey"
        },
        {
          "count": 231,
          "label": "Dîner",
          "value": "dinner"
        }
      ]
    }
  }
}
```

### Erreur de validation (400)
```json
{
  "success": false,
  "error": "Invalid query"
}
```

### Pas de données (404)
```json
{
  "success": false,
  "error": "No data"
}
```

### Erreur serveur (500)
```json
{
  "success": false,
  "error": "Database error message"
}
```

## Exemples d'utilisation

### Récupérer toutes les facettes pour Paris
```javascript
const response = await fetch('/v1/poi/facets?city=paris');
const { data } = await response.json();
// data.facets contient toutes les facettes disponibles
```

### Filtrer par quartier
```javascript
const response = await fetch('/v1/poi/facets?city=paris&neighbourhood_slug=haut-marais');
```

### Filtrer par catégorie et prix
```javascript
const response = await fetch('/v1/poi/facets?city=paris&category=restaurant&price=' + encodeURIComponent('€€'));
```

### Utiliser plusieurs tags (logique AND)
```javascript
const response = await fetch('/v1/poi/facets?city=paris&tags=trendy,terrace');
```

### Spécifier la langue
```javascript
const response = await fetch('/v1/poi/facets?city=paris&lang=en');
```

## Mapping des prix

Le frontend peut envoyer les prix en format lisible, l'API les convertit automatiquement :

| Frontend | API Interne |
|----------|-------------|
| `"€"` | `PRICE_LEVEL_INEXPENSIVE` |
| `"€€"` | `PRICE_LEVEL_MODERATE` |
| `"€€€"` | `PRICE_LEVEL_EXPENSIVE` |
| `"€€€€"` | `PRICE_LEVEL_VERY_EXPENSIVE` |

## Notes d'implémentation

1. **Conversion automatique des slugs** : Les `district_slug` et `neighbourhood_slug` sont automatiquement convertis en noms (ex: `"haut-marais"` → `"Haut Marais"`)

2. **Détection de langue** : Si `lang` n'est pas fourni, l'API utilise le header `Accept-Language` (défaut: `fr`)

3. **Filtrage contextuel** : Les facettes retournées sont déjà filtrées selon le contexte (ville, quartier, filtres appliqués)

4. **URL Encoding** : Pensez à encoder les caractères spéciaux dans l'URL (ex: `encodeURIComponent('€€')`)

## Cas d'usage frontend

### Construction d'une interface de filtres
```javascript
// 1. Charger les facettes initiales
const facets = await loadFacets({ city: 'paris' });

// 2. Construire les filtres UI
buildCategoryFilter(facets.category);
buildPriceFilter(facets.price);
buildTagsFilter(facets.tags);

// 3. Recharger les facettes quand l'utilisateur filtre
const updateFacets = async (filters) => {
  const params = new URLSearchParams(filters);
  const newFacets = await loadFacets(params);
  updateFiltersUI(newFacets);
};
```

### Exemple React Hook
```javascript
const usePOIFacets = (filters) => {
  const [facets, setFacets] = useState(null);
  const [loading, setLoading] = useState(false);
  
  useEffect(() => {
    const loadFacets = async () => {
      setLoading(true);
      try {
        const params = new URLSearchParams(filters);
        const response = await fetch(`/v1/poi/facets?${params}`);
        const data = await response.json();
        setFacets(data.data);
      } catch (error) {
        console.error('Error loading facets:', error);
      } finally {
        setLoading(false);
      }
    };
    
    loadFacets();
  }, [filters]);
  
  return { facets, loading };
};
```
