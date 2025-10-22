# Sitemap Endpoint Documentation

## Overview

The sitemap endpoint provides paginated access to all eligible POIs with their slug, last update timestamp, and Gatto score (0-5 scale) for use by the Next.js sitemap builder.

## Endpoint

```
GET /v1/sitemap/pois
```

## Query Parameters

| Parameter | Type    | Default | Min | Max    | Description              |
| --------- | ------- | ------- | --- | ------ | ------------------------ |
| `page`    | integer | `1`     | `1` | -      | Page number (1-indexed)  |
| `limit`   | integer | `500`   | `1` | `1000` | Number of items per page |

## Response Format

### Success Response (200 OK)

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "slug": "le-procope",
        "updated_at": "2024-01-15T10:30:00Z",
        "score": 4.5
      },
      {
        "slug": "cafe-de-flore",
        "updated_at": "2024-01-14T15:20:00Z",
        "score": 4.2
      }
    ],
    "pagination": {
      "total": 1234,
      "page": 1,
      "limit": 500,
      "has_next": true
    }
  },
  "timestamp": "2024-01-15T12:00:00Z"
}
```

### Error Response (500)

```json
{
  "success": false,
  "error": {
    "message": "Failed to build sitemap payload",
    "details": null,
    "timestamp": "2024-01-15T12:00:00Z"
  }
}
```

## Response Fields

### Items Array

Each item in the `items` array contains:

- **`slug`** (string): The POI's URL-friendly identifier. Prefers `slug_fr` with fallback to `slug_en`
- **`updated_at`** (string): ISO 8601 timestamp of the POI's last update
- **`score`** (number): Gatto score on 0-5 scale (converted from 0-100 internal score via `score / 20`)

### Pagination Object

- **`total`** (number): Total count of eligible POIs across all pages
- **`page`** (number): Current page number
- **`limit`** (number): Number of items per page (as requested, capped at 1000)
- **`has_next`** (boolean): Whether there are more pages available

## Business Logic

### Filtering

- Only includes POIs where `publishable_status = 'eligible'`
- Ordered by `updated_at DESC` for deterministic pagination

### Slug Selection

The endpoint prefers French slugs with English fallback:

```javascript
slug = poi.slug_fr || poi.slug_en;
```

### Score Conversion

Internal Gatto scores (0-100) are converted to the 0-5 scale for SEO priority:

```javascript
score05 = clamp(gatto_score / 20, 0, 5);
```

- POIs without a score in `latest_gatto_scores` default to `0`
- Score is rounded to 2 decimal places

### Pagination

Uses offset-based pagination:

```javascript
offset = (page - 1) * limit;
```

The `has_next` flag is calculated as:

```javascript
has_next = offset + items.length < total;
```

## Headers

### Response Headers

- **`Cache-Control`**: `public, max-age=300` (5 minutes)
- Standard Fastify headers (compression, CORS, etc.)

## Usage Examples

### Fetch First Page (Default)

```bash
curl https://api.gatto.app/v1/sitemap/pois
```

### Fetch with Custom Pagination

```bash
curl 'https://api.gatto.app/v1/sitemap/pois?page=2&limit=1000'
```

### Next.js Sitemap Integration

```typescript
// app/sitemap.xml/route.ts
export async function GET() {
  const allPois = [];
  let page = 1;
  let hasNext = true;

  // Fetch all pages
  while (hasNext) {
    const response = await fetch(
      `https://api.gatto.app/v1/sitemap/pois?page=${page}&limit=1000`,
      { next: { revalidate: 300 } } // 5 min cache
    );

    const { data } = await response.json();
    allPois.push(...data.items);
    hasNext = data.pagination.has_next;
    page++;
  }

  // Convert to sitemap entries
  const poiUrls = allPois.map((poi) => ({
    url: `https://gatto.app/poi/${poi.slug}`,
    lastModified: new Date(poi.updated_at),
    changeFrequency: "weekly",
    priority: Math.min(0.9, Math.max(0.1, poi.score / 5)),
  }));

  return generateSitemap(poiUrls);
}
```

## Performance Considerations

### Database Indexes

Required indexes for optimal performance (see `docs/sql/sitemap_indexes.sql`):

```sql
-- Filter index
CREATE INDEX poi_publishable_status_idx ON poi (publishable_status);

-- Order index
CREATE INDEX poi_updated_at_idx ON poi (updated_at DESC);

-- Composite index (optimal)
CREATE INDEX poi_sitemap_idx ON poi (publishable_status, updated_at DESC)
WHERE publishable_status = 'eligible';

-- Note: latest_gatto_scores is a view, it uses indexes from its source tables
```

### Query Optimization

- Uses Supabase's `count: 'exact'` for accurate total count
- Fetches scores in bulk via `IN` query to minimize round trips
- Limits enforced to prevent excessive load (max 1000 per page)

### Caching

- 5-minute HTTP cache via `Cache-Control` header
- Consider CDN caching for production (Cloudflare, Vercel Edge)
- Sitemap builders typically run on build/revalidate cycles

## Data Sources

### Tables

1. **`poi`**

   - Fields: `id`, `slug_fr`, `slug_en`, `updated_at`, `publishable_status`
   - Filter: `publishable_status = 'eligible'`

2. **`latest_gatto_scores`**
   - Fields: `poi_id`, `gatto_score` (0-100 scale)
   - Joined via `poi_id IN (...)`

## Error Handling

The endpoint handles errors gracefully:

- **Database errors**: Logged and returns 500 with generic error message
- **Missing scores**: Defaults to 0 (instead of failing)
- **Empty results**: Returns valid response with empty `items` array

## Monitoring

### Logs

Errors are logged with context:

```javascript
fastify.log.error({ err }, "GET /v1/sitemap/pois failed");
```

### Metrics to Track

- Response time per page
- Total POI count trends
- Cache hit rates
- Error rates

## Version History

- **v1.0** (2024-01-15): Initial implementation
  - Offset-based pagination
  - Score conversion to 0-5 scale
  - 5-minute HTTP caching
