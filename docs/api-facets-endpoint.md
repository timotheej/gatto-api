# API Facettes POI - Documentation Frontend

## Endpoint
`GET /v1/poi/facets`

## Description
Récupère les facettes contextuelles pour filtrer les POI (points d'intérêt) d'une ville donnée. Les facettes sont calculées en fonction des filtres appliqués et permettent un filtrage interactif.

## Paramètres de requête

| Paramètre | Type | Obligatoire | Défaut | Description |
|-----------|------|-------------|--------|-------------|
| `city` | string | Non | `"paris"` | Slug de la ville |
| `category` | string (CSV) | Non | - | Catégories séparées par des virgules (ex: `"bar,restaurant"`) |
| `subcategory` | string (CSV) | Non | - | Sous-catégories séparées par des virgules |
| `price` | integer | Non | - | Niveau de prix (1-4) où 1=€, 2=€€, 3=€€€, 4=€€€€ |
| `awarded` | boolean/string | Non | - | Filtre les POI primés (`"true"`, `"false"`, ou non spécifié) |
| `fresh` | boolean/string | Non | - | Filtre les nouveaux POI (`"true"`, `"false"`, ou non spécifié) |
| `district_slug` | string | Non | - | Slug de l'arrondissement (ex: `"marais"`) |
| `neighbourhood_slug` | string | Non | - | Slug du quartier |
| `tags` | string (CSV) | Non | - | Tags obligatoires (ET logique) |
| `tags_any` | string (CSV) | Non | - | Tags optionnels (OU logique) |
| `sort` | string | Non | `"gatto"` | Méthode de tri |
| `lang` | string | Non | `"fr"` | Langue des labels (`"fr"` ou `"en"`) |

## Format de réponse

```json
{
  "success": true,
  "data": {
    "context": {
      "city": "paris",
      "total_results": 274,
      "applied_filters": {
        "category": ["bar"],
        "price": ["2"],
        "awarded": true
      }
    },
    "facets": {
      "category": [
        {
          "value": "restaurant",
          "label": "Restaurant",
          "count": 177
        },
        {
          "value": "bar", 
          "label": "Bar",
          "count": 54
        }
      ],
      "subcategories": [
        {
          "value": "wine_bar",
          "label": "Wine Bar", 
          "count": 12
        }
      ],
      "price": [
        {
          "value": "1",
          "label": "€",
          "count": 17
        },
        {
          "value": "2", 
          "label": "€€",
          "count": 154
        }
      ],
      "districts": [
        {
          "value": "paris-11e-arrondissement",
          "label": "Paris 11e Arrondissement",
          "count": 32
        }
      ],
      "awards": [
        {
          "value": "michelin",
          "label": "Guide Michelin", 
          "count": 8
        },
        {
          "value": "gaultmillau",
          "label": "Gaultmillau",
          "count": 33
        }
      ]
    }
  }
}
```

## Structure des données

### Context
- `city`: La ville demandée
- `total_results`: Nombre total de POI correspondant aux filtres
- `applied_filters`: Objet contenant les filtres actuellement appliqués

### Facets
Chaque facette est un tableau d'objets contenant :
- `value`: Valeur technique à utiliser dans les paramètres
- `label`: Libellé à afficher à l'utilisateur  
- `count`: Nombre de POI correspondants si cette facette était sélectionnée

#### Types de facettes disponibles :
- **category**: Catégories principales (restaurant, bar, cafe, bakery...)
- **subcategories**: Sous-catégories spécialisées 
- **price**: Niveaux de prix (1-4)
- **districts**: Arrondissements/quartiers
- **awards**: Prix et distinctions (michelin, gaultmillau, timeout...)

## Exemples d'utilisation

### Récupérer toutes les facettes pour Paris
```javascript
fetch('/v1/poi/facets?city=paris')
  .then(res => res.json())
  .then(data => {
    console.log('Total POI:', data.data.context.total_results);
    console.log('Categories:', data.data.facets.category);
  });
```

### Filtrer par catégorie et prix
```javascript
const params = new URLSearchParams({
  city: 'paris',
  category: 'bar,restaurant',
  price: '2'
});

fetch(`/v1/poi/facets?${params}`)
  .then(res => res.json())
  .then(data => {
    // Les facettes sont contextuelles aux filtres appliqués
    console.log('Filtres appliqués:', data.data.context.applied_filters);
  });
```

### Recherche avec tags
```javascript
// Tags obligatoires (ET logique)
const tagsAll = 'natural_wine,organic';
// Tags optionnels (OU logique)  
const tagsAny = 'terrace,wifi';

fetch(`/v1/poi/facets?city=paris&tags=${tagsAll}&tags_any=${tagsAny}`)
  .then(res => res.json())
  .then(data => console.log(data));
```

## Notes importantes

### Performance et cache
- **Cache**: 5 minutes (`Cache-Control: public, max-age=300`)
- **Temps de réponse**: ~200ms en moyenne
- Le cache est partagé et basé sur l'URL complète

### Logique des facettes
- Les facettes sont **contextuelles** : elles reflètent les options disponibles en fonction des filtres déjà appliqués
- Les counts indiquent combien de POI seraient trouvés si cette facette était ajoutée
- Les facettes avec `count: 0` ne sont pas retournées
- Tri par `count` décroissant (sauf `price` trié par `value` croissant)

### Gestion des erreurs
- L'endpoint dispose d'un **fallback automatique** en cas d'erreur
- En cas d'échec total, retourne une erreur HTTP 500
- Les paramètres invalides retournent une erreur HTTP 400

### Compatibilité
- Compatible avec tous les filtres de l'endpoint `/v1/poi`
- Les `value` des facettes peuvent être directement utilisées comme paramètres de filtrage
- Format de réponse stable et rétrocompatible