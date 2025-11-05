# Testing Guide

## Manual Testing

### Prerequisites

1. Ensure environment variables are set (`.env` file)
2. Start the server: `npm run dev`
3. Have `curl` or a HTTP client installed

## Endpoint Tests

### 1. Health Check

```bash
curl http://localhost:3000/health
```

**Expected Response**:

```json
{
  "success": true,
  "data": { "status": "healthy" },
  "timestamp": "..."
}
```

### 2. API Info

```bash
curl http://localhost:3000/v1
```

**Expected Response**:

```json
{
  "success": true,
  "data": {
    "status": "ok",
    "version": "1.0",
    "endpoints": ["/v1/pois", "/v1/collections", "/v1/home", "/v1/sitemap/pois"],
    "uptime": 123
  },
  "timestamp": "..."
}
```

### 3. Sitemap POIs - Default Parameters

```bash
curl http://localhost:3000/v1/sitemap/pois
```

**Expected Response**:

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "slug": "example-poi",
        "updated_at": "2024-01-15T10:30:00Z",
        "score": 4.5
      }
    ],
    "pagination": {
      "total": 100,
      "page": 1,
      "limit": 500,
      "has_next": false
    }
  },
  "timestamp": "..."
}
```

**Validations**:

- ✅ `success` is `true`
- ✅ `data.items` is an array
- ✅ Each item has `slug`, `updated_at`, and `score`
- ✅ `score` is between 0 and 5
- ✅ `pagination.total` is a number
- ✅ `pagination.has_next` is boolean
- ✅ Response includes `Cache-Control` header

### 4. Sitemap POIs - Custom Pagination

```bash
# Page 2 with 100 items
curl 'http://localhost:3000/v1/sitemap/pois?page=2&limit=100'
```

**Expected Behavior**:

- Returns items 101-200
- `pagination.page` is `2`
- `pagination.limit` is `100`

### 5. Sitemap POIs - Maximum Limit

```bash
# Request 2000 items (should be clamped to 1000)
curl 'http://localhost:3000/v1/sitemap/pois?limit=2000'
```

**Expected Behavior**:

- `pagination.limit` is `1000` (clamped to max)
- Returns at most 1000 items

### 6. Sitemap POIs - Invalid Parameters

```bash
# Invalid page (should default to 1)
curl 'http://localhost:3000/v1/sitemap/pois?page=0'

# Invalid limit (should default to 500)
curl 'http://localhost:3000/v1/sitemap/pois?limit=abc'
```

**Expected Behavior**:

- Invalid `page` defaults to `1`
- Invalid `limit` defaults to `500`
- Response is still successful

### 7. Verify HTTP Headers

```bash
curl -I http://localhost:3000/v1/sitemap/pois
```

**Expected Headers**:

```
HTTP/1.1 200 OK
Cache-Control: public, max-age=300
Content-Type: application/json; charset=utf-8
```

## Integration Testing Scenarios

### Scenario 1: Empty Database

1. Clear all eligible POIs or set all to non-eligible status
2. Call endpoint
3. **Expected**: Empty items array, total = 0, has_next = false

### Scenario 2: POIs Without Scores

1. Ensure some POIs exist without entries in `latest_gatto_scores`
2. Call endpoint
3. **Expected**: POIs included with `score: 0`

### Scenario 3: Pagination Boundaries

1. Set up exactly 500 eligible POIs
2. Call with `?limit=500`
3. **Expected**: has_next = false
4. Set up 501 eligible POIs
5. Call with `?limit=500`
6. **Expected**: has_next = true

### Scenario 4: Slug Fallback

1. Create POI with only `slug_en` (no `slug_fr`)
2. Call endpoint
3. **Expected**: POI included with `slug` = `slug_en` value

### Scenario 5: Score Conversion

1. Create POI with `gatto_score = 100`
2. Call endpoint
3. **Expected**: `score = 5.00`
4. Create POI with `gatto_score = 50`
5. **Expected**: `score = 2.50`
6. Create POI with `gatto_score = 0`
7. **Expected**: `score = 0.00`

## Performance Testing

### Load Test

```bash
# Test 10 concurrent requests
for i in {1..10}; do
  curl http://localhost:3000/v1/sitemap/pois &
done
wait
```

### Large Dataset Test

```bash
# Request maximum page size
curl 'http://localhost:3000/v1/sitemap/pois?limit=1000'

# Measure response time
time curl 'http://localhost:3000/v1/sitemap/pois?limit=1000' > /dev/null 2>&1
```

**Performance Expectations**:

- Response time < 500ms for 1000 items (with indexes)
- Response time < 200ms for 500 items (with indexes)
- Memory usage remains stable under concurrent load

## Error Testing

### Database Connection Error

1. Stop Supabase or use invalid credentials
2. Call endpoint
3. **Expected**: 500 error with message "Failed to build sitemap payload"

### Rate Limiting

1. Make > 100 requests in 1 minute from same IP
2. **Expected**: 429 Too Many Requests

## Automated Test Script

```bash
#!/bin/bash

# Test script for sitemap endpoint
BASE_URL="http://localhost:3000"

echo "🧪 Running sitemap endpoint tests..."

# Test 1: Health check
echo "Test 1: Health check"
curl -s "$BASE_URL/health" | grep -q "healthy" && echo "✅ PASS" || echo "❌ FAIL"

# Test 2: Default pagination
echo "Test 2: Default pagination"
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois")
echo "$RESPONSE" | grep -q '"success":true' && echo "✅ PASS" || echo "❌ FAIL"

# Test 3: Custom pagination
echo "Test 3: Custom pagination"
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois?page=2&limit=100")
echo "$RESPONSE" | grep -q '"page":2' && echo "✅ PASS" || echo "❌ FAIL"

# Test 4: Limit clamping
echo "Test 4: Limit clamping"
RESPONSE=$(curl -s "$BASE_URL/v1/sitemap/pois?limit=2000")
echo "$RESPONSE" | grep -q '"limit":1000' && echo "✅ PASS" || echo "❌ FAIL"

# Test 5: Cache headers
echo "Test 5: Cache headers"
curl -sI "$BASE_URL/v1/sitemap/pois" | grep -q "Cache-Control: public, max-age=300" && echo "✅ PASS" || echo "❌ FAIL"

echo "✅ All tests completed!"
```

Save as `test-sitemap.sh`, make executable with `chmod +x test-sitemap.sh`, and run.

## Next.js Integration Test

```typescript
// Test in Next.js project
import { describe, it, expect } from "@jest/globals";

describe("Sitemap API Integration", () => {
  const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:3000";

  it("should fetch first page of POIs", async () => {
    const response = await fetch(`${API_URL}/v1/sitemap/pois`);
    const data = await response.json();

    expect(data.success).toBe(true);
    expect(data.data.items).toBeInstanceOf(Array);
    expect(data.data.pagination).toHaveProperty("total");
    expect(data.data.pagination).toHaveProperty("has_next");
  });

  it("should respect pagination parameters", async () => {
    const response = await fetch(`${API_URL}/v1/sitemap/pois?page=2&limit=100`);
    const data = await response.json();

    expect(data.data.pagination.page).toBe(2);
    expect(data.data.pagination.limit).toBe(100);
  });

  it("should return items with correct structure", async () => {
    const response = await fetch(`${API_URL}/v1/sitemap/pois`);
    const data = await response.json();

    if (data.data.items.length > 0) {
      const item = data.data.items[0];
      expect(item).toHaveProperty("slug");
      expect(item).toHaveProperty("updated_at");
      expect(item).toHaveProperty("score");
      expect(item.score).toBeGreaterThanOrEqual(0);
      expect(item.score).toBeLessThanOrEqual(5);
    }
  });

  it("should include cache headers", async () => {
    const response = await fetch(`${API_URL}/v1/sitemap/pois`);
    const cacheControl = response.headers.get("cache-control");

    expect(cacheControl).toContain("public");
    expect(cacheControl).toContain("max-age=300");
  });
});
```

## Troubleshooting

### Issue: Empty items array

- **Check**: Database has POIs with `publishable_status = 'eligible'`
- **Solution**: Insert eligible POIs or change status

### Issue: Scores are all 0

- **Check**: `latest_gatto_scores` table has data
- **Solution**: Run score calculation job or insert test scores

### Issue: Slow response times

- **Check**: Database indexes are created
- **Solution**: Run `docs/sql/sitemap_indexes.sql`

### Issue: 500 errors

- **Check**: Server logs for detailed error messages
- **Check**: Supabase connection is working
- **Solution**: Verify environment variables and database connection
