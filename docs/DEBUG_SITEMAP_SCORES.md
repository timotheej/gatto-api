# Diagnostic : Scores à 0 dans le Sitemap

## 🔍 Problème

L'endpoint `/v1/sitemap/pois` retourne tous les scores à `0` :

```json
{
  "slug": "le-fumoir",
  "updated_at": "2025-10-17T19:38:02.441075+00:00",
  "score": 0 // ❌ Toujours 0
}
```

## 🧪 Étapes de diagnostic

### 1. Vérifier les logs du serveur

Avec le logging ajouté, redémarrez le serveur et appelez l'endpoint :

```bash
# Dans un terminal, surveillez les logs
npm run dev

# Dans un autre terminal
curl http://localhost:3000/v1/sitemap/pois?limit=10
```

Cherchez dans les logs une ligne comme :

```
Sitemap scores fetch: {
  pois_count: 10,
  scores_count: 0,  // ⚠️ Si c'est 0, pas de scores trouvés
  sample_poi_ids: [...],
  sample_scores: [...]
}
```

### 2. Vérifier la base de données Supabase

Exécutez le script de diagnostic dans **Supabase SQL Editor** :

```bash
cat docs/sql/debug_sitemap_scores.sql
```

Copiez et exécutez dans Supabase. Voici ce que vous devriez voir :

#### ✅ Cas normal (scores présents)

```sql
-- Query 4: Scores pour POIs éligibles
id   | slug_fr        | gatto_score
-----|----------------|------------
123  | le-fumoir      | 75
456  | pizzeria-...   | 82
...
```

#### ❌ Cas problématique (pas de scores)

```sql
-- Query 4: Scores pour POIs éligibles
id   | slug_fr        | gatto_score
-----|----------------|------------
123  | le-fumoir      | NULL
456  | pizzeria-...   | NULL
...
```

### 3. Causes possibles et solutions

#### Cause A : La vue `latest_gatto_scores` est vide

**Diagnostic** :

```sql
SELECT COUNT(*) FROM latest_gatto_scores;
-- Résultat : 0
```

**Solution** : Vous devez calculer/générer les scores d'abord. Vérifiez :

- Avez-vous un job/script qui calcule les scores Gatto ?
- Les tables sources de la vue sont-elles peuplées ?

**Action** :

```sql
-- Vérifier la définition de la vue
SELECT pg_get_viewdef('latest_gatto_scores', true);
```

Puis exécutez votre processus de calcul des scores.

---

#### Cause B : Les `poi_id` ne correspondent pas

**Diagnostic** :

```sql
-- Comparer les types d'ID
SELECT
  p.id,
  pg_typeof(p.id) as poi_id_type,
  lgs.poi_id,
  pg_typeof(lgs.poi_id) as score_id_type
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible'
LIMIT 5;
```

**Problème possible** : Types différents (`uuid` vs `bigint`, etc.)

**Solution** : Adapter la jointure dans le code si nécessaire.

---

#### Cause C : La vue n'inclut que certains POIs

**Diagnostic** :

```sql
SELECT
  COUNT(DISTINCT p.id) as eligible_pois,
  COUNT(DISTINCT lgs.poi_id) as pois_with_scores
FROM poi p
LEFT JOIN latest_gatto_scores lgs ON p.id = lgs.poi_id
WHERE p.publishable_status = 'eligible';
```

Si `eligible_pois` > `pois_with_scores`, certains POIs n'ont pas de scores.

**Solutions** :

1. Vérifier les conditions de la vue `latest_gatto_scores`
2. S'assurer que le calcul des scores couvre tous les POIs éligibles

---

#### Cause D : Nom de colonne incorrect dans la vue

**Diagnostic** :

```sql
-- Vérifier les colonnes de la vue
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'latest_gatto_scores';
```

**Problèmes possibles** :

- La colonne s'appelle `score` au lieu de `gatto_score`
- La colonne s'appelle `id` au lieu de `poi_id`

**Solution** : Adapter le code JavaScript :

```javascript
// Dans routes/v1/sitemap.js
const { data: scores, error: scoresError } = await fastify.supabase
  .from("latest_gatto_scores")
  .select("id, score") // ⚠️ Adapter selon vos colonnes réelles
  .in("id", ids);

const scoreById = new Map(
  (scores || []).map((s) => [s.id, s.score]) // ⚠️ Adapter
);
```

---

## 🔧 Solution rapide : Vérification manuelle

Pour tester rapidement, faites une requête directe dans Supabase :

```sql
-- Prenez un poi_id d'un POI éligible
SELECT id FROM poi WHERE publishable_status = 'eligible' LIMIT 1;
-- Ex: résultat = '123e4567-e89b-12d3-a456-426614174000'

-- Cherchez son score
SELECT * FROM latest_gatto_scores
WHERE poi_id = '123e4567-e89b-12d3-a456-426614174000';
```

Si aucun résultat → le score n'existe pas  
Si résultat avec `gatto_score = NULL` → problème de calcul  
Si résultat avec `gatto_score = 75` → le problème est ailleurs (types, colonnes, etc.)

---

## 🛠️ Corrections potentielles du code

### Si le nom de colonne est différent

Vérifiez d'abord :

```sql
\d latest_gatto_scores  -- PostgreSQL
```

Puis adaptez `routes/v1/sitemap.js` :

```javascript
// Exemple : si la vue utilise "id" au lieu de "poi_id"
.select("id, gatto_score")  // au lieu de "poi_id, gatto_score"
.in("id", ids);             // au lieu de .in("poi_id", ids)

// Et adapter le Map
const scoreById = new Map(
  (scores || []).map((s) => [s.id, s.gatto_score])
);
```

---

## 📊 Monitoring permanent

Une fois corrigé, ajoutez une alerte si trop de scores sont à 0 :

```javascript
// Dans routes/v1/sitemap.js
const scoresCount = items.filter((i) => i.score > 0).length;
const scoresPercentage = (scoresCount / items.length) * 100;

if (scoresPercentage < 50) {
  fastify.log.warn(
    {
      total_items: items.length,
      items_with_scores: scoresCount,
      percentage: scoresPercentage,
    },
    "Low score coverage in sitemap"
  );
}
```

---

## ✅ Checklist de résolution

- [ ] Les logs montrent `scores_count > 0` ?
- [ ] La requête SQL 4 du debug montre des scores non-NULL ?
- [ ] Les `poi_id` correspondent entre `poi` et `latest_gatto_scores` ?
- [ ] Les noms de colonnes sont corrects (`poi_id` et `gatto_score`) ?
- [ ] La vue contient bien des données (`SELECT COUNT(*) FROM latest_gatto_scores`) ?
- [ ] Les types de données correspondent (UUID = UUID, etc.) ?

---

## 🆘 Besoin d'aide ?

Si le problème persiste, partagez :

1. Le résultat de la query 4 du script debug
2. Le résultat de `\d latest_gatto_scores`
3. Les logs du serveur avec le debug activé
