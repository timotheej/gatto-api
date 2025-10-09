# 🚀 Gatto API - Deployment Guide

## Production Readiness Checklist

### ✅ Environment Variables
Set these environment variables in your PaaS platform:

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here
SUPABASE_SERVICE_KEY=your_service_key_here
PORT=3100
NODE_ENV=production
CORS_ORIGIN=https://yourdomain.com,https://www.yourdomain.com
API_KEY_PUBLIC=your_secure_api_key_here
```

### 🔧 Supported PaaS Platforms

#### Railway
- Uses `railway.toml` configuration
- Auto-deploys from Git
- Built-in health checks

#### Render
- Uses `Dockerfile` 
- Set environment variables in dashboard
- Enable auto-deploy from Git

#### Heroku
- Uses `Procfile`
- Configure buildpacks: `heroku/nodejs`
- Set config vars via CLI or dashboard

#### Fly.io
- Uses `Dockerfile`
- Configure via `fly.toml` (to be created)
- Deploy with `flyctl deploy`

### 🛡️ Security Features
- ✅ Helmet.js for security headers
- ✅ Rate limiting (100 req/min)
- ✅ CORS configuration
- ✅ API key authentication
- ✅ Input validation
- ✅ Compression (gzip, brotli)

### 📊 Performance Features  
- ✅ Response compression
- ✅ ETags for caching
- ✅ Cache headers (5min)
- ✅ Connection pooling
- ✅ Optimized database queries

### 🏥 Health Monitoring
- Health endpoint: `GET /health`
- Structured logging
- Error handling with proper HTTP codes
- Docker health checks included

### 🚀 Quick Deploy Commands

#### Docker
```bash
docker build -t gatto-api .
docker run -p 3100:3100 --env-file .env gatto-api
```

#### Railway
```bash
railway login
railway link
railway up
```

#### Render
- Connect GitHub repository
- Set build command: `npm install`
- Set start command: `npm start`

### 📝 Notes
- Node.js 18+ required
- No build step needed (vanilla JS)
- Uses ES modules (type: "module")
- Supabase handles database connections