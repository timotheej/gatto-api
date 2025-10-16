import { z } from 'zod';


// Utility functions for parameter parsing
function parseCsvToArray(str, { lowercase = false } = {}) {
  if (!str || typeof str !== 'string') return null;
  const arr = str
    .split(',')
    .map(s => s.trim())
    .filter(Boolean)
    .map(s => (lowercase ? s.toLowerCase() : s));
  return arr.length ? arr : null;
}

function parseSingleFromCsv(str, { lowercase = false } = {}) {
  const arr = parseCsvToArray(str, { lowercase });
  return arr?.[0] ?? null;
}

function parseBoolTriState(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v !== 'string') return null;
  if (v === 'true') return true;
  if (v === 'false') return false;
  return null;
}

function parsePriceBound(value) {
  if (value === undefined || value === null) return null;
  const parsed = parseInt(String(value), 10);
  if (Number.isNaN(parsed)) return null;
  if (parsed < 1 || parsed > 4) return null;
  return parsed;
}

function parseRatingBound(value) {
  if (value === undefined || value === null) return null;
  const parsed = Number.parseFloat(String(value));
  if (Number.isNaN(parsed)) return null;
  if (parsed < 0 || parsed > 5) return null;
  return parsed;
}

// Validation schema
const QuerySchema = z.object({
  city: z.string().default('paris'),
  district_slug: z.string().optional(),
  neighbourhood_slug: z.string().optional(),
  category: z.string().optional(),
  subcategory: z.string().optional(),
  price: z.string().optional(),
  awarded: z.string().optional(),
  fresh: z.string().optional(),
  awards: z.string().optional(),
  tags: z.string().optional(),
  tags_any: z.string().optional(),
  sort: z.string().optional(),
  price_min: z.string().optional(),
  price_max: z.string().optional(),
  rating_min: z.string().optional(),
  rating_max: z.string().optional(),
  lang: z.string().optional()
}).strict();


/**
 * Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).
 */
export default async function poiFacetsRoutes(fastify) {
  fastify.get('/v1/poi/facets', {
    schema: {
      description: 'Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).',
      tags: ['POI']
    }
  }, async (request, reply) => {
    // 1) Parse & validate
    const parsed = QuerySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.code(400).send({ success: false, error: 'Invalid query' });
    }
    
    const q = request.query || {};

    const categorySlug        = parseSingleFromCsv(q.category, { lowercase: true });
    const categories          = categorySlug ? [categorySlug] : null;
    const subcategories       = parseCsvToArray(q.subcategory, { lowercase: true });
    const tagsAll             = parseCsvToArray(q.tags, { lowercase: true });
    const tagsAny             = parseCsvToArray(q.tags_any, { lowercase: true });
    const awardsProviders     = parseCsvToArray(q.awards, { lowercase: true });
    const districtSlugs       = parseCsvToArray(q.district_slug, { lowercase: true });
    const neighbourhoodSlugs  = parseCsvToArray(q.neighbourhood_slug, { lowercase: true });
    let priceMin              = parsePriceBound(q.price_min);
    let priceMax              = parsePriceBound(q.price_max);
    const ratingMin           = parseRatingBound(q.rating_min);
    const ratingMax           = parseRatingBound(q.rating_max);

    // Compat: legacy single price maps to exact range
    const legacyPrice = parsePriceBound(q.price);
    if (legacyPrice !== null) {
      priceMin = priceMin ?? legacyPrice;
      priceMax = priceMax ?? legacyPrice;
    }

    const awarded             = parseBoolTriState(q.awarded);
    const fresh               = parseBoolTriState(q.fresh);

    const rpcParams = {
      p_city_slug:           q.city || 'paris',
      p_categories:          categories,
      p_subcategories:       subcategories,
      p_price_min:           priceMin,
      p_price_max:           priceMax,
      p_rating_min:          ratingMin,
      p_rating_max:          ratingMax,
      p_district_slugs:      districtSlugs,
      p_neighbourhood_slugs: neighbourhoodSlugs,
      p_tags_all:            tagsAll,
      p_tags_any:            tagsAny,
      p_awarded:             awarded,    // null/true/false
      p_fresh:               fresh,      // null/true/false
      p_lang:                q.lang || 'fr',
      p_sort:                q.sort || 'gatto'
    };

    // Only add p_awards_providers if it's not null
    if (awardsProviders !== null) {
      rpcParams.p_awards_providers = awardsProviders;
    }

    // Appel RPC
    try {
      const { data, error } = await fastify.supabase.rpc('rpc_get_poi_facets', rpcParams);
      if (error) {
        fastify.log.error({ err: error, rpcParams }, 'rpc_get_poi_facets failed');
        return reply.code(500).send({ success: false, error: 'Failed to compute facets' });
      }
      
      // La RPC renvoie déjà le format JSON correct { context, facets }
      const payload = data;
      
      // Réponse HTTP (cache aligné sur /v1/poi)
      reply.header('Cache-Control', 'public, max-age=300');
      return reply.send({ success: true, data: payload });
      
    } catch (e) {
      fastify.log.error({ e, rpcParams }, 'Exception in rpc_get_poi_facets');
      return reply.code(500).send({ success: false, error: 'Failed to compute facets' });
    }

  });
}
