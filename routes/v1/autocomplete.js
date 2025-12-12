import { LRUCache } from 'lru-cache';
import { z } from 'zod';
import { recordAutocomplete } from '../../utils/searchMetrics.js';

/**
 * Autocomplete endpoint for search suggestions
 * Returns POIs + Types matching the query
 */

// ==== CACHE CONFIGURATION ====

// LRU cache for autocomplete responses (1 minute TTL, max 1000 entries)
// Short TTL because autocomplete should be relatively fresh
const autocompleteCache = new LRUCache({
  max: 1000,              // Max 1000 entries (more than pois cache due to varied queries)
  ttl: 1000 * 60 * 1,     // 1 minute TTL
  updateAgeOnGet: true,   // Reset TTL on cache hit
  updateAgeOnHas: false
});

// Generate stable cache key from params
function getCacheKey(params) {
  const sortedParams = Object.keys(params)
    .sort()
    .reduce((acc, key) => {
      if (params[key] !== undefined && params[key] !== null) {
        acc[key] = params[key];
      }
      return acc;
    }, {});
  return `autocomplete:${JSON.stringify(sortedParams)}`;
}

// ==== VALIDATION SCHEMA ====

const AutocompleteQuerySchema = z.object({
  q: z.string()
    .min(1, 'Query must be at least 1 character')
    .max(200, 'Query must be at most 200 characters'),

  city: z.string()
    .min(1)
    .max(200)
    .regex(/^[a-z0-9-]+$/, 'City must be lowercase alphanumeric with dashes')
    .default('paris'),

  lang: z.enum(['fr', 'en']).default('fr'),

  limit: z.coerce.number().int().min(1).max(50).default(7)  // Hick's Law: 7±2
}).strict();

// ==== ROUTES ====

export default async function autocompleteRoutes(fastify) {

  // GET /v1/autocomplete - Autocomplete suggestions
  fastify.get('/autocomplete', async (request, reply) => {
    const startTime = Date.now(); // Track response time
    let cacheHit = false;
    let hasError = false;

    try {
      // Validate query parameters with Zod
      const validatedQuery = AutocompleteQuerySchema.parse(request.query);

      const { q, city, lang, limit } = validatedQuery;

      // Check cache
      const cacheKey = getCacheKey({ q, city, lang, limit });
      const cached = autocompleteCache.get(cacheKey);
      if (cached) {
        cacheHit = true;
        const responseTime = Date.now() - startTime;
        recordAutocomplete({ query: q, cache_hit: true, response_time_ms: responseTime });

        fastify.log.info({ cacheKey, endpoint: '/v1/autocomplete', response_time_ms: responseTime }, 'Cache HIT');
        reply.header('X-Cache', 'HIT');
        reply.header('Cache-Control', 'public, max-age=60');
        return reply.send(cached);
      }

      fastify.log.info({ cacheKey, endpoint: '/v1/autocomplete', query: q }, 'Cache MISS');

      // Call autocomplete RPC
      const { data: rows, error } = await fastify.supabase.rpc('autocomplete_search', {
        p_query: q,
        p_city_slug: city,
        p_lang: lang,
        p_limit: limit
      });

      if (error) {
        hasError = true;
        const responseTime = Date.now() - startTime;
        recordAutocomplete({ query: q, cache_hit: false, response_time_ms: responseTime, error: true });

        fastify.log.error('RPC autocomplete_search error:', error);
        return reply.code(500).send({
          success: false,
          error: 'Failed to fetch autocomplete suggestions',
          timestamp: new Date().toISOString()
        });
      }

      const suggestions = rows || [];

      // Build response with optimized structure
      const response = {
        success: true,
        data: {
          suggestions: suggestions.map(s => {
            // For POIs: include metadata with type_label, district, city
            if (s.type === 'poi') {
              return {
                type: 'poi',
                value: s.poi_slug || s.value,  // Use slug, fallback to ID
                display: s.display,
                metadata: {
                  type_label: s.poi_type_label,
                  district: s.poi_district,
                  city: s.poi_city
                }
              };
            }

            // For types: no metadata
            return {
              type: s.type,
              value: s.value,
              display: s.display,
              metadata: null
            };
          })
        },
        timestamp: new Date().toISOString()
      };

      // Store in cache
      autocompleteCache.set(cacheKey, response);

      // Record metrics for cache miss
      const responseTime = Date.now() - startTime;
      recordAutocomplete({ query: q, cache_hit: false, response_time_ms: responseTime });

      // Send response
      reply.header('X-Cache', 'MISS');
      reply.header('Cache-Control', 'public, max-age=60');
      return reply.send(response);

    } catch (err) {
      // Record error metrics
      const responseTime = Date.now() - startTime;
      recordAutocomplete({ query: request.query?.q || 'unknown', cache_hit: cacheHit, response_time_ms: responseTime, error: true });

      // Handle Zod validation errors
      if (err.name === 'ZodError') {
        return reply.code(400).send({
          success: false,
          error: 'Invalid query parameters',
          details: err.issues.map(issue => ({
            field: issue.path.join('.'),
            message: issue.message,
            code: issue.code
          })),
          timestamp: new Date().toISOString()
        });
      }

      // Handle other errors
      fastify.log.error('GET /autocomplete error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });
}
