# Filtres POI : guide d’intégration frontend

Ce guide résume les nouvelles possibilités offertes par les endpoints `/v1/poi` (liste) et `/v1/poi/facets` afin de garantir une expérience cohérente côté client.

## Principes généraux

- **Ville & tri obligatoires** : toujours envoyer `city=<slug>` et `sort=<clé>` dans vos requêtes (`gatto`, `price_desc`, `price_asc`, `mentions`, `rating`).  
- **Filtres symétriques** : chaque valeur envoyée à `/v1/poi` doit être reportée à `/v1/poi/facets` (sauf `cursor`/`limit`) pour obtenir des compteurs cohérents.
- **CSV normalisés** : toutes les listes multiples utilisent des valeurs séparées par des virgules, sans espaces (`bar,restaurant`).  
- **Absence = filtre désactivé** : ne pas envoyer un paramètre lorsque le filtre est “off”.  
- **Single vs multi** : `category` reste single-choice ; les autres familles sont multi et appliquent une logique **OR**.

## Paramètres disponibles

| Groupe              | Endpoint(s)          | Paramètres                         | Notes frontend                                                   |
|---------------------|----------------------|------------------------------------|------------------------------------------------------------------|
| Ville & tri         | liste + facettes     | `city`, `sort`                     | toujours requis pour aligner les compteurs.                     |
| Catégorie           | liste + facettes     | `category=<slug>`                  | un seul slug à la fois (radio).                                 |
| Sous-catégories     | liste + facettes     | `subcategory=<slug1,slug2>`        | logique OR : un POI matche s’il possède au moins une valeur.    |
| Arrondissements     | liste + facettes     | `district_slug=<slug1,slug2>`      | logique OR.                                                      |
| Quartiers           | liste + facettes     | `neighbourhood_slug=<slug1,slug2>` | logique OR (prépare la future UX “quartiers”).                  |
| Filtres géo legacy  | liste uniquement     | `district`, `neighbourhood`        | recherche partielle (legacy) en plus des slugs exacts.          |
| Prix (range)        | liste + facettes     | `price_min`, `price_max`           | bornes inclusives 1..4. `price` (single) mappe vers un range exact. |
| Note (range)        | liste + facettes     | `rating_min`, `rating_max`         | bornes inclusives 0..5. Facette retourne `rating_range`.        |
| Awards              | liste + facettes     | `awards=<provider1,provider2>`     | logique OR (ex : `michelin,timeout`).                           |
| Booléens            | liste + facettes     | `awarded`, `fresh`                 | tri-state (`true`, `false`, absence).                           |
| Tags AND/OR         | liste + facettes     | `tags`, `tags_any`                 | `tags` = AND, `tags_any` = OR.                                  |
| Tags “providers”    | liste + facettes     | `awards`                           | normalisés en lowercase par l’API.                              |

> ℹ️ Les paramètres `cursor`/`limit` restent propres à `/v1/poi` et ne doivent pas être transmis à `/v1/poi/facets`.

## Recommandations d’implémentation

1. **Synchroniser les URL**  
   Concaténez et encodez les CSV dès le state management front. Unhook/rehook des filtres déclenche à la fois `getPoiList(query)` et `getPoiFacets(queryWithoutCursorLimit)`.

2. **Slider prix**  
   - Utilisez `price_levels` renvoyé par les facettes pour construire vos graduations.  
   - L’API répond déjà avec `price` → `[min,max]` dans `context.applied_filters`.

3. **Slider rating**  
   - `rating_range.min/max` donne les limites disponibles après filtrage.  
   - Snappez vos sliders sur `0.1` ou `0.5` selon UX ; l’API accepte le flottant.

4. **Badges d’état**  
   - Réutilisez `context.applied_filters` pour afficher les chips actives (catégorie, sous-catégories, prix, rating, districts, awards, etc.)

5. **Pagination**  
   - Rangez `next_cursor` renvoyé par `/v1/poi` et réinjectez-le via `cursor` pour charger la page suivante.  
   - Ne l’envoyez jamais aux facettes.

6. **Fallbacks legacy**  
   - `price` seul => filtre exact (ex : bouton €€) ; l’API le projette en (`price_min=price_max=2`).  
   - `district` / `neighbourhood` (texte libre) restent supportés pour compatibilité mais évitez-les si vous disposez de slugs.

## Exemples pratiques

### Restaurants français notés entre 4.5 et 5

```http
GET /v1/poi?city=paris&category=restaurant&subcategory=french_restaurant&rating_min=4.5&rating_max=5&sort=rating
GET /v1/poi/facets?city=paris&category=restaurant&subcategory=french_restaurant&rating_min=4.5&rating_max=5&sort=rating
```

### Mix prix + awards + géo

```http
GET /v1/poi?city=paris&district_slug=paris-10e-arrondissement,paris-11e-arrondissement&awards=michelin,timeout&price_min=2&price_max=4&sort=price_desc
GET /v1/poi/facets?city=paris&district_slug=paris-10e-arrondissement,paris-11e-arrondissement&awards=michelin,timeout&price_min=2&price_max=4&sort=price_desc
```

### OR sur sous-catégories et tags_any

```http
GET /v1/poi?city=lyon&category=bar&subcategory=wine_bar,cocktail_bar&tags_any=natural_wine,craft_beer&sort=mentions
GET /v1/poi/facets?city=lyon&category=bar&subcategory=wine_bar,cocktail_bar&tags_any=natural_wine,craft_beer&sort=mentions
```

## À surveiller côté UX

- Restreindre les combos impossibles : ex. slider prix bloqué à `[1,4]` uniquement.  
- Mettre à jour les chips summary lorsque les facettes renvoient des listes vides (afficher “Aucun résultat”).  
- Les comptes sont déjà filtrés : inutile de recalculer côté front, mais pensez à gérer `0`.

En suivant ces conventions, l’interface reste alignée avec la logique serveur et les utilisateurs bénéficient de compteurs toujours cohérents.***
