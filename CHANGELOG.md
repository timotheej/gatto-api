# Changelog

All notable changes to the Gatto API project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added - 2024-10-22

#### Sitemap Endpoint for SEO

- **New route**: `GET /v1/sitemap/pois` - Paginated endpoint for sitemap generation
  - Returns all eligible POIs with slug, updated_at, and Gatto score (0-5)
  - Supports pagination with `page` (default: 1) and `limit` (default: 500, max: 1000) query params
  - Filters POIs by `publishable_status = 'eligible'`
  - Converts Gatto scores from 0-100 to 0-5 scale for SEO priority calculation
  - Returns pagination metadata including `total`, `page`, `limit`, and `has_next`
  - HTTP caching with `Cache-Control: public, max-age=300` (5 minutes)

#### Files Added

- `routes/v1/sitemap.js` - Sitemap route implementation
- `docs/SITEMAP_ENDPOINT.md` - Comprehensive endpoint documentation
- `docs/TESTING.md` - Testing guide with manual and automated test scenarios
- `docs/sql/sitemap_indexes.sql` - Database indexes for optimal query performance
- `docs/sql/README.md` - SQL scripts documentation

#### Files Modified

- `server.js` - Registered sitemap route
- `routes/v1/index.js` - Added sitemap endpoint to API info
- `README.md` - Updated with sitemap endpoint documentation

#### Database Indexes (Optional but Recommended)

- `poi_publishable_status_idx` - Index on `poi.publishable_status`
- `poi_updated_at_idx` - Index on `poi.updated_at DESC`
- `poi_sitemap_idx` - Composite index on `(publishable_status, updated_at DESC)` with WHERE clause
- Note: `latest_gatto_scores` is a view and uses indexes from its source tables

#### Features

- **Slug selection**: Prefers `slug_fr`, falls back to `slug_en`
- **Score conversion**: Converts 0-100 internal score to 0-5 scale via `score / 20`
- **Defensive defaults**: POIs without scores default to 0 instead of failing
- **Pagination safety**: Validates and clamps parameters to safe bounds
- **Error handling**: Graceful error handling with proper logging
- **Performance**: Bulk score fetching with O(1) lookup via Map
- **Deterministic ordering**: Orders by `updated_at DESC` for stable pagination

#### Integration

- Compatible with Next.js sitemap builder
- Frontend can iterate pages until `has_next = false`
- Priority calculation in frontend: `priority = Math.min(0.9, Math.max(0.1, score / 5))`

#### Documentation

- Full API documentation in `docs/SITEMAP_ENDPOINT.md`
- Testing guide with scenarios in `docs/TESTING.md`
- Database optimization guide in `docs/sql/README.md`
- Updated main README with usage examples

---

## [1.0.0] - Initial Release

### Added

- Fastify server with plugin architecture
- Supabase integration via `@supabase/supabase-js`
- Security plugins: Helmet, CORS, Rate Limiting
- i18n support with language detection
- Response helpers (`reply.success()` and `reply.error()`)
- POI routes:
  - `GET /v1/poi` - Paginated list with advanced filtering
  - `GET /v1/poi/:slug` - POI detail view
- Collections route: `GET /v1/collections`
- Home route: `GET /v1/home`
- Health check: `GET /health`
- API info: `GET /v1`

### Infrastructure

- Docker support
- Railway and Fly.io deployment configurations
- Environment-based configuration
- Compression (gzip, brotli)
- ETag support for HTTP caching
