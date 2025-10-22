# SQL Scripts

This directory contains SQL scripts for database migrations and optimizations.

## Files

### `sitemap_indexes.sql`

Database indexes to optimize the `/v1/sitemap/pois` endpoint performance.

**Purpose**: Improves query performance for the sitemap builder by adding indexes on:

- `poi.publishable_status` - for filtering eligible POIs
- `poi.updated_at` - for ordering by last update
- Composite index on `(publishable_status, updated_at)` - for optimal query execution

**Note**: `latest_gatto_scores` is a view, so it automatically benefits from indexes on its underlying source tables.

**When to run**:

- During initial deployment of the sitemap feature
- If sitemap endpoint queries are slow

**How to run**:

1. Open Supabase SQL Editor
2. Copy and paste the contents of `sitemap_indexes.sql`
3. Execute the script
4. Verify indexes were created:
   ```sql
   SELECT indexname, indexdef
   FROM pg_indexes
   WHERE tablename IN ('poi', 'latest_gatto_scores');
   ```

**Impact**:

- Minimal impact on writes (indexes are maintained automatically)
- Significant improvement in sitemap query performance
- Recommended for production environments

## Best Practices

1. Always test migrations in a staging environment first
2. Review index usage periodically with `EXPLAIN ANALYZE`
3. Monitor index sizes and query performance
4. Keep this directory in sync with production schema
