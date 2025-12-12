# Frontend Integration - Search V1

Guide d'intégration pour implémenter la recherche côté front-end.

## Vue d'ensemble

Le système de recherche V1 permet de:
- **Rechercher par type** : "italien", "restaurant japonais" → détection automatique du type
- **Rechercher par nom** : "Comptoir", "Pink Mamma" → fuzzy matching avec score de relevance
- **Autocomplete** : suggestions en temps réel (types + POIs)

---

## 1. Autocomplete

### Endpoint
```
GET /v1/autocomplete
```

### Paramètres
| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `q` | string | ✅ | - | Query de recherche (min 1 char) |
| `city` | string | ❌ | `paris` | Slug de la ville |
| `lang` | string | ❌ | `fr` | Langue (`fr` ou `en`) |
| `limit` | number | ❌ | `7` | Nombre de suggestions (max 50, optimal 7) |

### Réponse
```typescript
{
  success: true,
  data: {
    suggestions: [
      {
        type: "type",
        value: "italian_restaurant",
        display: "Restaurant italien",
        metadata: null
      },
      {
        type: "poi",
        value: "pink-mamma-paris",  // Slug du POI
        display: "Pink Mamma",
        metadata: {
          type_label: "Restaurant italien",
          district: "11e arr.",
          city: "Paris"
        }
      }
    ]
  },
  timestamp: "2025-12-12T15:00:00.000Z"
}
```

### Exemple d'implémentation

```typescript
// React Hook pour autocomplete avec debounce
import { useState, useEffect } from 'react';

function useAutocomplete(query: string, delay = 300) {
  const [suggestions, setSuggestions] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!query || query.length < 2) {
      setSuggestions([]);
      return;
    }

    const timer = setTimeout(async () => {
      setLoading(true);
      try {
        const response = await fetch(
          `/v1/autocomplete?q=${encodeURIComponent(query)}&city=paris&lang=fr&limit=7`,
          {
            headers: {
              'x-api-key': process.env.NEXT_PUBLIC_API_KEY
            }
          }
        );
        const data = await response.json();

        if (data.success) {
          setSuggestions(data.data.suggestions);
        }
      } catch (error) {
        console.error('Autocomplete error:', error);
      } finally {
        setLoading(false);
      }
    }, delay);

    return () => clearTimeout(timer);
  }, [query, delay]);

  return { suggestions, loading };
}

// Utilisation dans un composant
function SearchBar() {
  const [query, setQuery] = useState('');
  const { suggestions, loading } = useAutocomplete(query);

  const handleSelect = (suggestion) => {
    if (suggestion.type === 'type') {
      // Rediriger vers /search?q=italien
      router.push(`/search?q=${encodeURIComponent(query)}`);
    } else {
      // Rediriger vers /poi/[slug] (suggestion.value est le slug)
      router.push(`/poi/${suggestion.value}`);
    }
  };

  return (
    <div>
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder="Restaurant, type de cuisine..."
      />
      {loading && <Spinner />}
      {suggestions.length > 0 && (
        <ul className="autocomplete-dropdown">
          {suggestions.map((s, i) => (
            <li key={i} onClick={() => handleSelect(s)}>
              {/* TYPE : afficher juste le label */}
              {s.type === 'type' && (
                <div>
                  <span className="icon">🍝</span>
                  {s.display}
                </div>
              )}

              {/* POI : afficher nom + metadata */}
              {s.type === 'poi' && s.metadata && (
                <div>
                  <strong>{s.display}</strong>
                  <span className="meta">
                    {s.metadata.type_label} · {s.metadata.district}
                  </span>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
```

---

## 2. Search (List POIs)

### Endpoint
```
GET /v1/pois
```

### Nouveaux paramètres

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | ❌ | Query de recherche (type ou nom) |
| `sort` | string | ❌ | Ajout de `relevance` (nécessite `q`) |
| `name_similarity_threshold` | number | ❌ | Seuil fuzzy matching (0-1, défaut 0.3) |

### Comportement

**Sans `q`** : Backward compatible (filtrage classique)
```bash
GET /v1/pois?city=paris&type_keys=italian_restaurant&limit=20
# → 164 restaurants italiens
```

**Avec `q` (type search)** : Détection automatique du type
```bash
GET /v1/pois?q=italien&city=paris&limit=20
# → Détecte "italian_restaurant" automatiquement
# → Équivalent à type_keys=italian_restaurant
```

**Avec `q` (name search)** : Recherche par nom avec relevance
```bash
GET /v1/pois?q=comptoir&city=paris&sort=relevance&limit=20
# → POIs avec "Comptoir" dans le nom
# → Triés par score de relevance (décroissant)
```

### Réponse (avec name search)

```typescript
{
  success: true,
  data: {
    items: [
      {
        id: "poi_123",
        name: "Comptoir Sur Mer",
        slug: "comptoir-sur-mer",
        primary_type: "seafood_restaurant",
        // ... autres champs POI
        name_relevance_score: 0.529412  // Uniquement si q fourni + name search
      }
    ],
    pagination: {
      page: 1,
      limit: 20,
      total: 5,
      total_pages: 1
    }
  }
}
```

### Exemple d'implémentation

```typescript
// Page de résultats de recherche
function SearchResults({ query }: { query: string }) {
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchResults() {
      setLoading(true);
      try {
        // Construction de l'URL selon le type de recherche
        const params = new URLSearchParams({
          q: query,
          city: 'paris',
          lang: 'fr',
          limit: '20',
          page: '1'
        });

        // Si recherche par nom, ajouter sort=relevance
        if (isNameSearch(query)) {
          params.append('sort', 'relevance');
        }

        const response = await fetch(`/v1/pois?${params}`, {
          headers: {
            'x-api-key': process.env.NEXT_PUBLIC_API_KEY
          }
        });

        const data = await response.json();

        if (data.success) {
          setResults(data.data.items);
        }
      } catch (error) {
        console.error('Search error:', error);
      } finally {
        setLoading(false);
      }
    }

    fetchResults();
  }, [query]);

  return (
    <div>
      <h1>Résultats pour "{query}"</h1>
      {loading ? (
        <Spinner />
      ) : (
        <div>
          {results.map((poi) => (
            <PoiCard
              key={poi.id}
              poi={poi}
              relevanceScore={poi.name_relevance_score}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// Helper pour détecter si c'est une recherche par nom
function isNameSearch(query: string): boolean {
  // Si query commence par une majuscule ou contient des mots spécifiques
  // → probablement un nom de restaurant
  return /^[A-Z]/.test(query) || query.includes(' ');
}
```

---

## 3. Facets avec recherche

### Endpoint
```
GET /v1/pois/facets
```

### Nouveaux paramètres

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | ❌ | Query de recherche (type uniquement) |

**Note** : Les facets ne supportent que les **type searches**. Les name searches sont ignorées.

### Exemple

```typescript
// Récupérer les facettes pour une recherche
async function getFacets(query: string) {
  const response = await fetch(
    `/v1/pois/facets?q=${encodeURIComponent(query)}&city=paris`,
    {
      headers: {
        'x-api-key': process.env.NEXT_PUBLIC_API_KEY
      }
    }
  );

  const data = await response.json();

  if (data.success) {
    // data.data.facets.bbox.tags → Tags disponibles pour cette recherche
    // data.data.facets.bbox.districts → Quartiers où il y a des résultats
    // data.data.facets.bbox.price_ranges → Prix disponibles
    return data.data.facets;
  }
}
```

---

## 4. Flux UX recommandé

### Scénario 1 : Recherche par type

```
1. User tape "italien" dans la barre de recherche
2. Autocomplete affiche "Restaurant italien (type)" (relevance: 1.0)
3. User sélectionne → Redirect vers /search?q=italien
4. Frontend appelle /v1/pois?q=italien&city=paris
5. API détecte type_keys=['italian_restaurant']
6. Affiche 164 restaurants italiens
```

### Scénario 2 : Recherche par nom

```
1. User tape "Pink" dans la barre de recherche
2. Autocomplete affiche "Pink Mamma · italian_restaurant" (relevance: 0.85)
3. User sélectionne → Redirect vers /poi/pink-mamma (direct)
OU
3. User appuie sur Enter → Redirect vers /search?q=Pink
4. Frontend appelle /v1/pois?q=Pink&city=paris&sort=relevance
5. API fait un fuzzy search sur les noms
6. Affiche POIs avec "Pink" dans le nom, triés par relevance
```

### Scénario 3 : Multi-word query

```
1. User tape "restaurant italien"
2. Autocomplete affiche "Restaurant italien (type)" (relevance: 0.98)
3. User sélectionne → /search?q=restaurant+italien
4. API détecte type_keys=['italian_restaurant']
5. Affiche restaurants italiens
```

---

## 5. Cache & Performance

### Headers de cache

L'API retourne des headers de cache pour optimiser les performances:

```typescript
// Autocomplete
Cache-Control: public, max-age=60
X-Cache: HIT | MISS

// POIs
Cache-Control: public, max-age=300
```

### Recommandations frontend

1. **Debounce** : Attendre 300ms avant d'appeler l'autocomplete
2. **Min length** : Ne pas appeler l'API si query < 2 caractères
3. **Cache client** : Utiliser React Query ou SWR pour cacher les résultats
4. **Pagination** : Charger 20 résultats par page (défaut API)

```typescript
// Exemple avec React Query
import { useQuery } from '@tanstack/react-query';

function useSearchPois(query: string) {
  return useQuery({
    queryKey: ['pois', 'search', query],
    queryFn: async () => {
      const response = await fetch(`/v1/pois?q=${encodeURIComponent(query)}&city=paris`);
      return response.json();
    },
    enabled: query.length >= 2,
    staleTime: 5 * 60 * 1000, // 5 min
    cacheTime: 10 * 60 * 1000, // 10 min
  });
}
```

---

## 6. Gestion des erreurs

### Validation Errors (400)

```typescript
{
  success: false,
  error: "Invalid query parameters",
  details: [
    {
      field: "q",
      message: "Query parameter 'q' is required when sort='relevance'",
      code: "custom"
    }
  ],
  timestamp: "2025-12-12T15:00:00.000Z"
}
```

### Server Errors (500)

```typescript
{
  success: false,
  error: "Failed to fetch POIs",
  timestamp: "2025-12-12T15:00:00.000Z"
}
```

### Exemple de gestion

```typescript
async function searchPois(query: string) {
  try {
    const response = await fetch(`/v1/pois?q=${encodeURIComponent(query)}`);
    const data = await response.json();

    if (!data.success) {
      if (response.status === 400) {
        // Validation error
        console.error('Validation error:', data.details);
        showToast('Paramètres de recherche invalides');
      } else {
        // Server error
        console.error('Server error:', data.error);
        showToast('Erreur lors de la recherche');
      }
      return null;
    }

    return data.data;
  } catch (error) {
    console.error('Network error:', error);
    showToast('Erreur de connexion');
    return null;
  }
}
```

---

## 7. Types TypeScript

```typescript
// Autocomplete
interface POIMetadata {
  type_label: string;   // Type traduit ("Restaurant italien")
  district: string;     // Arrondissement court ("11e arr.")
  city: string;         // Ville ("Paris")
}

interface AutocompleteSuggestion {
  type: 'type' | 'poi';
  value: string;        // type_key ou slug du POI
  display: string;      // Label à afficher
  metadata: POIMetadata | null;  // Metadata uniquement pour POIs
}

interface AutocompleteResponse {
  success: boolean;
  data: {
    suggestions: AutocompleteSuggestion[];
  };
  timestamp: string;
}

// Search
interface POI {
  id: string;
  name: string;
  slug: string;
  primary_type: string;
  // ... autres champs
  name_relevance_score?: number; // Présent uniquement si q fourni + name search
}

interface SearchResponse {
  success: boolean;
  data: {
    items: POI[];
    pagination: {
      page: number;
      limit: number;
      total: number;
      total_pages: number;
    };
  };
  timestamp: string;
}

// Error
interface ErrorResponse {
  success: false;
  error: string;
  details?: Array<{
    field: string;
    message: string;
    code: string;
  }>;
  timestamp: string;
}
```

---

## 8. Limites & Contraintes

- **Rate limiting** : 60 requêtes/minute par API key
- **Query max length** : 200 caractères
- **Autocomplete limit** : Max 50 suggestions
- **POIs limit** : Max 50 POIs par page
- **Fuzzy threshold** : 0.3 par défaut (ajustable avec `name_similarity_threshold`)

---

## 9. Monitoring

L'endpoint `/v1/metrics` permet de monitorer les performances:

```typescript
GET /v1/metrics

{
  success: true,
  data: {
    autocomplete: {
      total_requests: 150,
      cache_hit_rate: "65.00%",
      avg_response_time_ms: 45,
      popular_queries: [
        { query: "italien", count: 30 },
        { query: "restaurant", count: 25 }
      ]
    },
    search: {
      total_requests: 80,
      cache_hit_rate: "40.00%",
      name_searches: 20,
      type_searches: 60
    }
  }
}
```

---

**Date** : 2025-12-12
**Version** : Search V1
**API Base URL** : `http://localhost:3100` (dev) | `https://api.gatto.com` (prod)
