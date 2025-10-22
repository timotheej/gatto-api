# Quick Start: Sitemap Endpoint

## 🎯 Purpose

Provides a paginated API endpoint to feed the Next.js sitemap builder with all eligible POIs and their metadata.

## 🚀 Quick Usage

### Basic Request

```bash
curl https://api.gatto.app/v1/sitemap/pois
```

### With Pagination

```bash
curl 'https://api.gatto.app/v1/sitemap/pois?page=2&limit=1000'
```

## 📋 Response Structure

```javascript
{
  success: true,
  data: {
    items: [
      {
        slug: "le-procope",           // POI slug (prefers FR, falls back to EN)
        updated_at: "2024-01-15T...", // Last update timestamp
        score: 4.5                     // Gatto score on 0-5 scale
      }
    ],
    pagination: {
      total: 1234,      // Total eligible POIs
      page: 1,          // Current page
      limit: 500,       // Items per page
      has_next: true    // More pages available?
    }
  },
  timestamp: "..."
}
```

## 🔧 Implementation Checklist

### Backend (Done ✅)

- [x] Create `routes/v1/sitemap.js`
- [x] Register route in `server.js`
- [x] Update API info endpoint
- [x] Add documentation
- [x] Create SQL indexes

### Database (To Do)

- [ ] Run `docs/sql/sitemap_indexes.sql` in Supabase SQL Editor
- [ ] Verify indexes with:
  ```sql
  SELECT indexname, indexdef FROM pg_indexes
  WHERE tablename IN ('poi', 'latest_gatto_scores');
  ```

### Frontend (Next.js Integration)

```typescript
// app/sitemap.xml/route.ts
import { MetadataRoute } from "next";

export async function GET() {
  const allPois = [];
  let page = 1;
  let hasNext = true;

  // Fetch all pages
  while (hasNext) {
    const res = await fetch(
      `${process.env.API_URL}/v1/sitemap/pois?page=${page}&limit=1000`,
      { next: { revalidate: 300 } }
    );
    const { data } = await res.json();

    allPois.push(...data.items);
    hasNext = data.pagination.has_next;
    page++;
  }

  // Generate sitemap
  const urls: MetadataRoute.Sitemap = allPois.map((poi) => ({
    url: `https://gatto.app/poi/${poi.slug}`,
    lastModified: new Date(poi.updated_at),
    changeFrequency: "weekly",
    priority: Math.min(0.9, Math.max(0.1, poi.score / 5)),
  }));

  return Response.json(urls);
}
```

## 🧪 Testing

### 1. Start Server

```bash
npm run dev
```

### 2. Test Endpoint

```bash
# Default pagination
curl http://localhost:3000/v1/sitemap/pois

# Custom pagination
curl 'http://localhost:3000/v1/sitemap/pois?page=2&limit=100'

# Check headers
curl -I http://localhost:3000/v1/sitemap/pois
```

### 3. Verify Response

- ✅ `success: true`
- ✅ `items` is an array
- ✅ Each item has `slug`, `updated_at`, `score`
- ✅ `score` is between 0 and 5
- ✅ `Cache-Control: public, max-age=300` header present

## 📊 Expected Performance

| Dataset Size | Response Time | Notes        |
| ------------ | ------------- | ------------ |
| 500 items    | < 200ms       | With indexes |
| 1000 items   | < 500ms       | With indexes |
| First page   | < 100ms       | Cached count |

## 🐛 Troubleshooting

### Empty Items Array

**Problem**: `items: []` returned  
**Solution**: Check database has POIs with `publishable_status = 'eligible'`

### All Scores Are 0

**Problem**: All POIs have `score: 0`  
**Solution**: Verify `latest_gatto_scores` table has data

### Slow Responses

**Problem**: Response time > 1s  
**Solution**: Run `docs/sql/sitemap_indexes.sql` to create indexes

### 500 Errors

**Problem**: Server returns error  
**Solution**: Check server logs and Supabase connection

## 🔐 Security

- ✅ Rate limited: 100 requests/minute per IP
- ✅ CORS enabled for allowed origins
- ✅ No authentication required (public data)
- ✅ Input validation on query params
- ✅ SQL injection protected (parameterized queries)

## 📈 Monitoring

### Key Metrics

- Request count per hour
- Average response time
- Cache hit rate
- Error rate

### Logs to Watch

```bash
# Error logs
grep "GET /v1/sitemap/pois failed" logs/

# Performance logs
grep "sitemap" logs/ | grep "duration"
```

## 🚀 Deployment

### Environment Variables Required

```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJxxx...
SUPABASE_SERVICE_KEY=eyJxxx...
PORT=3000
NODE_ENV=production
```

### Post-Deployment Checklist

1. [ ] Verify endpoint responds: `curl https://api.gatto.app/v1/sitemap/pois`
2. [ ] Check cache headers present
3. [ ] Run indexes in production database
4. [ ] Monitor response times
5. [ ] Update Next.js sitemap to use new endpoint
6. [ ] Test full sitemap generation
7. [ ] Submit sitemap to Google Search Console

## 📚 Further Reading

- Full API documentation: [`docs/SITEMAP_ENDPOINT.md`](./SITEMAP_ENDPOINT.md)
- Testing guide: [`docs/TESTING.md`](./TESTING.md)
- Database indexes: [`docs/sql/sitemap_indexes.sql`](./sql/sitemap_indexes.sql)
- Main README: [`../README.md`](../README.md)

## 💡 Tips

1. **Pagination**: Use max limit (1000) for faster sitemap generation
2. **Caching**: The 5-minute cache reduces DB load during builds
3. **Monitoring**: Track response times to detect index issues
4. **Scores**: Default score of 0 ensures all eligible POIs are included
5. **Ordering**: `updated_at DESC` ensures recently updated POIs appear first

## ❓ FAQ

**Q: Why 0-5 instead of 0-100?**  
A: SEO sitemap priorities are typically 0-1, calculated as `score/5`. This makes integration simpler.

**Q: Why max 1000 items per page?**  
A: Supabase PostgREST has practical limits. 1000 balances performance with fewer requests.

**Q: What if a POI has no score?**  
A: Defaults to 0. All eligible POIs are included regardless of score.

**Q: Can I change the cache duration?**  
A: Yes, modify `max-age=300` in `routes/v1/sitemap.js` line 101.

**Q: How often should the sitemap rebuild?**  
A: Recommended: On-demand (ISR in Next.js) with 5-minute revalidation.
