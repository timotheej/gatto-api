# Autocomplete API - Structure optimisée

Structure finale de la réponse `/v1/autocomplete` pour le dropdown.

---

## Response Structure

```json
{
  "success": true,
  "data": {
    "suggestions": [
      {
        "type": "type",
        "value": "italian_restaurant",
        "display": "Restaurant italien",
        "metadata": null
      },
      {
        "type": "type",
        "value": "pizzeria",
        "display": "Pizzeria",
        "metadata": null
      },
      {
        "type": "poi",
        "value": "pink-mamma-paris",
        "display": "Pink Mamma",
        "metadata": {
          "type_label": "Restaurant italien",
          "district": "11e arr.",
          "city": "Paris"
        }
      },
      {
        "type": "poi",
        "value": "eataly-paris",
        "display": "Eataly",
        "metadata": {
          "type_label": "Épicerie italienne",
          "district": "2e arr.",
          "city": "Paris"
        }
      }
    ]
  },
  "timestamp": "2025-12-12T16:00:00.000Z"
}
```

---

## Champs

### Suggestion Object

| Champ | Type | Description |
|-------|------|-------------|
| `type` | string | `"type"` ou `"poi"` (usage interne, pas affiché) |
| `value` | string | type_key ou slug du POI |
| `display` | string | Texte principal à afficher |
| `metadata` | object\|null | Infos supplémentaires (null pour types) |

### Metadata (pour POIs uniquement)

| Champ | Type | Description |
|-------|------|-------------|
| `type_label` | string | Type traduit ("Restaurant italien") |
| `district` | string | Arrondissement court ("11e arr.") |
| `city` | string | Ville ("Paris") |

---

## Affichage Front-End

### TYPE
```
🍝 Restaurant italien
```

### POI
```
Pink Mamma · Restaurant italien · 11e arr.
```

Ou en deux lignes si mobile:
```
Pink Mamma
Restaurant italien · 11e arr.
```

---

## Limites

- **Max suggestions** : 7 (Loi de Hick: 7±2)
  - Ratio flexible (ex: 4 types + 3 POIs, ou 2 types + 5 POIs)
- **Pas de count** visible
- **Pas de relevance** visible
- **Pas de photo**
- **Pas de badge/price/rating**

---

## Suggestions populaires (query vide)

Endpoint: `GET /v1/autocomplete/popular` ou `GET /v1/autocomplete?q=`

```json
{
  "success": true,
  "data": {
    "suggestions": [
      {
        "type": "type",
        "value": "italian_restaurant",
        "display": "Restaurant italien",
        "metadata": null
      },
      {
        "type": "type",
        "value": "japanese_restaurant",
        "display": "Restaurant japonais",
        "metadata": null
      },
      {
        "type": "type",
        "value": "brunch",
        "display": "Brunch",
        "metadata": null
      }
    ]
  }
}
```

**Logique** : Top 5-7 types les plus recherchés (à déterminer: globalement ou par ville).

---

## Modifications nécessaires

### 1. RPC `autocomplete_search`

Ajouter les champs manquants pour POIs:
- `district` (label court)
- `city`
- `type_label` (traduit selon lang)

### 2. Nouveau endpoint ou paramètre

Pour les suggestions populaires:
- Option A: `GET /v1/autocomplete?q=` (query vide retourne populaires)
- Option B: `GET /v1/autocomplete/popular`

### 3. Table de tracking

Pour calculer "les plus recherchés":
- Soit: agrégation des métriques existantes (searchMetrics.js)
- Soit: nouvelle table `popular_searches` avec counts

---

**Date** : 2025-12-12
**Version** : Autocomplete V1 - Structure finale
