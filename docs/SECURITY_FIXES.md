# 🛠️ Corrections de Sécurité - Guide d'Application

Ce document contient les corrections à appliquer **immédiatement** suite à l'audit de sécurité.

---

## 🔴 URGENCE 1: Supprimer secrets de git (5 min)

### Étape 1: Supprimer .env.backup du repo

```bash
# 1. Supprimer du tracking git
git rm --cached .env.backup

# 2. Ajouter au .gitignore
echo "" >> .gitignore
echo "# Backup files with secrets" >> .gitignore
echo ".env.backup" >> .gitignore
echo "*.backup" >> .gitignore

# 3. Commit
git add .gitignore
git commit -m "security: remove .env.backup from git tracking"

# 4. Push
git push origin main
```

### Étape 2: Régénérer les clés Supabase

**⚠️ IMPORTANT**: La clé actuelle est exposée dans git, elle DOIT être révoquée.

1. **Aller sur Supabase Dashboard**:
   - https://supabase.com/dashboard/project/cuwrsdssoonlwypboarg
   - Settings > API

2. **Révoquer l'ancienne clé**:
   - Cliquer sur "Revoke" pour `service_role` key
   - Confirmer la révocation

3. **Générer une nouvelle clé**:
   - Cliquer sur "Generate new service_role key"
   - Copier la nouvelle clé

4. **Mettre à jour Fly.io secrets**:
   ```bash
   flyctl secrets set SUPABASE_SERVICE_ROLE_KEY="nouvelle_clé_ici" -a gatto-api
   ```

5. **Mettre à jour .env local** (créer si n'existe pas):
   ```bash
   cat > .env << 'EOF'
   SUPABASE_URL=https://cuwrsdssoonlwypboarg.supabase.co
   SUPABASE_SERVICE_ROLE_KEY=nouvelle_clé_ici
   PORT=3000
   NODE_ENV=development
   CORS_ORIGIN=https://gatto.city,https://www.gatto.city
   API_KEY_PUBLIC=générer_une_nouvelle_clé_forte
   EOF
   ```

6. **Générer une vraie API key**:
   ```bash
   # Générer une clé aléatoire forte
   node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
   ```

### Étape 3: Redéployer

```bash
# Redémarrer l'app avec la nouvelle clé
flyctl deploy -a gatto-api
```

---

## 🔴 URGENCE 2: Corriger CORS (10 min)

**Fichier**: `plugins/cors.js`

### Avant (DANGEREUX):
```javascript
await fastify.register(cors, {
  origin: process.env.NODE_ENV === 'development' ? true : corsOrigins, // ⚠️
  credentials: true,
  // ...
});
```

### Après (SÉCURISÉ):
```javascript
// Combiner origines selon environnement
const allowedOrigins = process.env.NODE_ENV === 'development'
  ? [...defaultOrigins, ...localOrigins]
  : corsOrigins;

await fastify.register(cors, {
  origin: allowedOrigins, // ✅ Toujours une liste blanche
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key']
});

// Remplacer console.log par logger
fastify.log.debug({ allowedOrigins }, 'CORS configured');
```

---

## 🔴 URGENCE 3: Activer authentification (15 min)

### Option A: Protection globale (recommandé)

**Fichier**: `server.js`

Ajouter AVANT l'enregistrement des routes:

```javascript
// Après les plugins, AVANT les routes
await fastify.register(responsesPlugin);

// ✅ Ajouter cette section
// Protection API key globale
fastify.addHook('onRequest', async (request, reply) => {
  // Routes publiques (whitelist)
  const publicRoutes = [
    '/health',
    '/v1',  // Info endpoint
  ];

  // Vérifier si la route est publique
  if (publicRoutes.includes(request.url) || request.url === '/') {
    return; // Permettre l'accès
  }

  // Vérifier API key pour toutes les autres routes
  const apiKey = request.headers['x-api-key'];
  const validKey = process.env.API_KEY_PUBLIC;

  if (!validKey) {
    fastify.log.error('API_KEY_PUBLIC not configured');
    return reply.code(500).send({
      success: false,
      error: 'Server configuration error',
      timestamp: new Date().toISOString()
    });
  }

  if (!apiKey || apiKey !== validKey) {
    fastify.log.warn({
      ip: request.ip,
      url: request.url,
      providedKey: apiKey ? `${apiKey.substring(0, 8)}...` : 'none'
    }, 'Unauthorized access attempt');

    return reply.code(401).send({
      success: false,
      error: 'Unauthorized - Invalid or missing API key',
      timestamp: new Date().toISOString()
    });
  }

  // API key valide, continuer
  fastify.log.debug({ url: request.url }, 'Authenticated request');
});

// Puis les routes
await fastify.register(v1Routes, { prefix: "/v1" });
// ...
```

### Option B: Protection par route

**Fichier**: `routes/v1/pois.js`

```javascript
// Ajouter config.protected sur chaque route
fastify.get('/pois', {
  config: { protected: true }
}, async (request, reply) => {
  // ...
});

fastify.get('/pois/:slug', {
  config: { protected: true }
}, async (request, reply) => {
  // ...
});
```

**ET** modifier `plugins/security.js` pour supprimer le bypass:

```javascript
// SUPPRIMER ces lignes dangereuses:
if (process.env.NODE_ENV === 'development') {
  return; // ❌ SUPPRIMER
}

const devKeys = ['dev_key', 'development', 'local'];
if (process.env.NODE_ENV !== 'production' && devKeys.includes(apiKey)) {
  return; // ❌ SUPPRIMER
}
```

---

## 🔴 URGENCE 4: Corriger Rate Limiting (5 min)

**Fichier**: `plugins/rate-limit.js`

### Avant:
```javascript
await fastify.register(rateLimit, {
  max: 100,
  timeWindow: '1 minute'
});
```

### Après:
```javascript
await fastify.register(rateLimit, {
  max: 30, // ✅ 30 req/min au lieu de 100
  timeWindow: '1 minute',
  cache: 10000,
  errorResponseBuilder: (_, context) => {
    return {
      code: 429,
      error: 'Too Many Requests',
      message: `Rate limit exceeded (${context.max} req/min). Retry in ${Math.ceil(context.ttl / 1000)}s`,
      date: Date.now(),
      expiresIn: context.ttl
    };
  },
  // Whitelist localhost en dev
  allowList: process.env.NODE_ENV === 'development' ? ['127.0.0.1', '::1'] : []
});
```

---

## 🟠 IMPORTANT: Validation stricte avec Zod (30 min)

### Installation (déjà fait)
Zod est déjà dans package.json ✅

### Créer les schémas de validation

**Nouveau fichier**: `utils/validation.js`

```javascript
import { z } from 'zod';

// Schéma pour GET /v1/pois
export const PoisQuerySchema = z.object({
  bbox: z.string()
    .regex(/^-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*,-?\d+\.?\d*$/, 'Invalid bbox format')
    .refine(bbox => {
      const [latMin, lngMin, latMax, lngMax] = bbox.split(',').map(Number);
      return latMin >= -90 && latMin <= 90 &&
             latMax >= -90 && latMax <= 90 &&
             lngMin >= -180 && lngMin <= 180 &&
             lngMax >= -180 && lngMax <= 180 &&
             latMin < latMax && lngMin < lngMax;
    }, 'Invalid bbox coordinates'),

  city: z.string()
    .min(1).max(50)
    .regex(/^[a-z0-9-]+$/, 'City must be lowercase alphanumeric with dashes')
    .default('paris'),

  primary_type: z.string()
    .max(200)
    .regex(/^[a-z0-9_,]+$/, 'Invalid primary_type format')
    .optional(),

  subcategory: z.string()
    .max(200)
    .regex(/^[a-z0-9_,]+$/, 'Invalid subcategory format')
    .optional(),

  neighbourhood_slug: z.string()
    .max(200)
    .regex(/^[a-z0-9-,]+$/, 'Invalid neighbourhood_slug format')
    .optional(),

  district_slug: z.string()
    .max(200)
    .regex(/^[a-z0-9-,]+$/, 'Invalid district_slug format')
    .optional(),

  tags: z.string()
    .max(200)
    .regex(/^[a-z0-9_,]+$/, 'Invalid tags format')
    .optional(),

  tags_any: z.string()
    .max(200)
    .regex(/^[a-z0-9_,]+$/, 'Invalid tags_any format')
    .optional(),

  awards: z.string()
    .max(200)
    .regex(/^[a-z0-9_,]+$/, 'Invalid awards format')
    .optional(),

  awarded: z.enum(['true', 'false']).optional(),

  fresh: z.enum(['true', 'false']).optional(),

  price: z.coerce.number().int().min(1).max(4).optional(),
  price_min: z.coerce.number().int().min(1).max(4).optional(),
  price_max: z.coerce.number().int().min(1).max(4).optional(),

  rating_min: z.coerce.number().min(0).max(5).optional(),
  rating_max: z.coerce.number().min(0).max(5).optional(),

  sort: z.enum(['gatto', 'price_desc', 'price_asc', 'mentions', 'rating'])
    .default('gatto'),

  limit: z.coerce.number().int().min(1).max(80).default(50),

  lang: z.enum(['fr', 'en']).default('fr')
}).strict(); // ✅ Rejette les paramètres inconnus

// Schéma pour GET /v1/pois/:slug
export const PoiDetailParamsSchema = z.object({
  slug: z.string()
    .min(1).max(200)
    .regex(/^[a-z0-9-]+$/, 'Slug must be lowercase alphanumeric with dashes')
});

export const PoiDetailQuerySchema = z.object({
  lang: z.enum(['fr', 'en']).default('fr')
}).strict();
```

### Utiliser dans les routes

**Fichier**: `routes/v1/pois.js`

```javascript
import { PoisQuerySchema, PoiDetailParamsSchema, PoiDetailQuerySchema } from '../utils/validation.js';

export default async function poisRoutes(fastify) {
  // GET /v1/pois
  fastify.get('/pois', async (request, reply) => {
    try {
      // ✅ Validation stricte avec Zod
      const validatedQuery = PoisQuerySchema.parse(request.query);

      // Utiliser validatedQuery au lieu de request.query
      const {
        bbox,
        city,
        primary_type,
        // ... tous les paramètres validés
      } = validatedQuery;

      // ... reste du code
    } catch (error) {
      if (error.name === 'ZodError') {
        return reply.code(400).send({
          success: false,
          error: 'Invalid query parameters',
          details: error.errors.map(e => ({
            field: e.path.join('.'),
            message: e.message
          })),
          timestamp: new Date().toISOString()
        });
      }
      throw error;
    }
  });

  // GET /v1/pois/:slug
  fastify.get('/pois/:slug', async (request, reply) => {
    try {
      const validatedParams = PoiDetailParamsSchema.parse(request.params);
      const validatedQuery = PoiDetailQuerySchema.parse(request.query);

      const { slug } = validatedParams;
      const { lang } = validatedQuery;

      // ... reste du code
    } catch (error) {
      if (error.name === 'ZodError') {
        return reply.code(400).send({
          success: false,
          error: 'Invalid parameters',
          details: error.errors.map(e => ({
            field: e.path.join('.'),
            message: e.message
          })),
          timestamp: new Date().toISOString()
        });
      }
      throw error;
    }
  });
}
```

---

## 🟠 IMPORTANT: Améliorer les headers de sécurité (10 min)

**Fichier**: `plugins/security.js`

```javascript
await fastify.register(helmet, {
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'"], // ✅ Supprimer unsafe-inline
      scriptSrc: ["'self'"],
      imgSrc: [
        "'self'",
        "data:",
        "https://cuwrsdssoonlwypboarg.supabase.co" // ✅ Spécifique au CDN
      ],
      connectSrc: [
        "'self'",
        "https://cuwrsdssoonlwypboarg.supabase.co"
      ]
    }
  },
  frameguard: {
    action: 'deny' // ✅ Empêche iframe (clickjacking)
  },
  noSniff: true, // ✅ X-Content-Type-Options: nosniff
  hsts: {
    maxAge: 31536000, // ✅ 1 an de HSTS
    includeSubDomains: true,
    preload: true
  },
  referrerPolicy: {
    policy: 'strict-origin-when-cross-origin'
  }
});

// Supprimer les bypass dangereux
// ❌ SUPPRIMER:
// if (process.env.NODE_ENV === 'development') { return; }
// if (devKeys.includes(apiKey)) { return; }

// ✅ GARDER seulement:
fastify.addHook('preHandler', async (request, reply) => {
  const routeConfig = request.routeOptions?.config;

  if (routeConfig && routeConfig.protected) {
    const apiKey = request.headers['x-api-key'];
    const expectedKey = process.env.API_KEY_PUBLIC;

    if (!apiKey || apiKey !== expectedKey) {
      reply.code(401);
      throw new Error('Invalid or missing API key');
    }
  }
});
```

---

## 📋 Checklist d'Application

### Phase 1: Urgence (30 min)
- [ ] Supprimer .env.backup de git
- [ ] Régénérer clés Supabase
- [ ] Mettre à jour secrets Fly.io
- [ ] Corriger CORS (supprimer `origin: true`)
- [ ] Réduire rate limit à 30 req/min
- [ ] Redéployer l'API

### Phase 2: Important (2h)
- [ ] Activer authentification globale
- [ ] Créer utils/validation.js
- [ ] Ajouter validation Zod sur /v1/pois
- [ ] Ajouter validation Zod sur /v1/pois/:slug
- [ ] Améliorer headers de sécurité
- [ ] Tester tous les endpoints

### Phase 3: Vérification (30 min)
- [ ] Tester avec curl sans API key → doit retourner 401
- [ ] Tester avec curl + API key → doit fonctionner
- [ ] Tester avec paramètres invalides → doit retourner 400
- [ ] Vérifier les logs (pas de secrets exposés)
- [ ] Vérifier CORS (seulement origines autorisées)

---

## 🧪 Tests après corrections

### Test 1: API key requise
```bash
# Sans API key → doit échouer
curl https://api.gatto.city/v1/pois?bbox=2.25,48.81,2.42,48.90
# Attendu: 401 Unauthorized

# Avec API key → doit fonctionner
curl -H "x-api-key: votre_clé" https://api.gatto.city/v1/pois?bbox=2.25,48.81,2.42,48.90
# Attendu: 200 OK
```

### Test 2: Validation des paramètres
```bash
# Bbox invalide → doit échouer
curl -H "x-api-key: votre_clé" https://api.gatto.city/v1/pois?bbox=invalid
# Attendu: 400 Bad Request avec détails Zod

# Paramètre inconnu → doit échouer
curl -H "x-api-key: votre_clé" "https://api.gatto.city/v1/pois?bbox=2.25,48.81,2.42,48.90&hack=true"
# Attendu: 400 Bad Request (strict mode)
```

### Test 3: Rate limiting
```bash
# 31 requêtes rapides → la 31ème doit être limitée
for i in {1..31}; do
  curl -H "x-api-key: votre_clé" https://api.gatto.city/v1/pois?bbox=2.25,48.81,2.42,48.90
done
# Attendu: 30x 200 OK, puis 429 Too Many Requests
```

### Test 4: CORS
```javascript
// Dans la console du navigateur sur evil.com
fetch('https://api.gatto.city/v1/pois?bbox=2.25,48.81,2.42,48.90', {
  headers: { 'x-api-key': 'test' }
})
// Attendu: CORS error (bloqué par le navigateur)
```

---

## 📞 Support

Si tu rencontres des problèmes lors de l'application:
1. Vérifier les logs: `flyctl logs -a gatto-api`
2. Tester en local d'abord: `npm run dev`
3. Revenir en arrière si nécessaire: `git revert HEAD`

---

**Temps total estimé**: 3-4 heures
**Gain de sécurité**: 🔴 Critique → 🟢 Production-ready
