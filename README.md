# Gatto API

Backend API pour le projet Gatto utilisant Fastify et Supabase.

## 🚀 Démarrage rapide

### Installation

```bash
npm install
```

### Configuration

1. Copiez le fichier `.env.example` vers `.env`
2. Remplissez les variables d'environnement requises

```bash
cp .env.example .env
```

### Démarrage

```bash
# Mode production
npm start

# Mode développement (avec watch)
npm run dev
```

L'API sera disponible sur `http://localhost:3000`

## 📁 Structure du projet

```
/api/
├── server.js              # Point d'entrée principal
├── plugins/               # Plugins Fastify
│   ├── supabase.js        # Client Supabase
│   ├── cors.js            # Configuration CORS
│   ├── security.js        # Sécurité et authentification
│   ├── i18n.js            # Internationalisation
│   └── rate-limit.js      # Limitation de taux
├── routes/
│   └── v1/                # Routes API v1
│       ├── index.js       # Route racine /v1
│       ├── poi.js         # Points d'intérêt
│       ├── collections.js # Collections
│       └── home.js        # Page d'accueil
├── utils/
│   └── responses.js       # Helpers de réponse
└── .env.example          # Variables d'environnement
```

## 🔧 Configuration

### Variables d'environnement

- `SUPABASE_URL` - URL de votre projet Supabase
- `SUPABASE_ANON_KEY` - Clé anonyme Supabase
- `SUPABASE_SERVICE_KEY` - Clé de service Supabase
- `PORT` - Port du serveur (défaut: 3000)
- `NODE_ENV` - Environnement (production/development)
- `CORS_ORIGIN` - Origines CORS autorisées
- `API_KEY_PUBLIC` - Clé API publique pour l'authentification

## 🛡️ Sécurité

- **CORS** configuré pour `gatto.city` et `www.gatto.city`
- **Rate limiting** : 100 requêtes/minute/IP
- **Helmet** pour les headers de sécurité
- **API Key** protection pour les routes protégées
- **Compression** gzip/brotli activée
- **ETag** pour le cache HTTP

## 🌐 Endpoints

### Routes principales

- `GET /health` - Health check
- `GET /v1` - Informations API et liste des endpoints

### Routes v1

- `GET /v1/poi` - Points d'intérêt (à implémenter)
- `GET /v1/collections` - Collections (à implémenter)
- `GET /v1/home` - Page d'accueil (à implémenter)

### Paramètres

- `?lang=fr|en` - Langue (français par défaut)

### Réponses

Format de réponse standardisé :

```json
{
  "success": true,
  "data": {},
  "timestamp": "2023-..."
}
```

Format d'erreur :

```json
{
  "success": false,
  "error": {
    "message": "...",
    "details": null,
    "timestamp": "2023-..."
  }
}
```

## 🔌 Plugins

- **Supabase** : Client global accessible via `fastify.supabase`
- **CORS** : Configuration multi-domaines
- **Security** : Protection API key + Helmet
- **i18n** : Détection langue via query param
- **Rate Limit** : Protection contre le spam
- **Responses** : Helpers `reply.success()` et `reply.error()`

## 📦 Déploiement

Le projet est configuré pour être déployé sur :
- **Vercel** (recommandé)
- **Render**
- Tout service supportant Node.js

Assurez-vous de configurer les variables d'environnement sur votre plateforme de déploiement.