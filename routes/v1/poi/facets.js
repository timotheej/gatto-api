import { z } from 'zod';


// Utility functions for parameter parsing
function parseCsvToArray(str) {
  if (!str || typeof str !== 'string') return null;
  const arr = str.split(',').map(s => s.trim()).filter(Boolean);
  return arr.length ? arr : null;
}

function parseBoolTriState(v) {
  if (typeof v === 'boolean') return v;
  if (typeof v !== 'string') return null;
  if (v === 'true') return true;
  if (v === 'false') return false;
  return null;
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

    const categories          = parseCsvToArray(q.category);
    const subcategories       = parseCsvToArray(q.subcategory);
    const tagsAll             = parseCsvToArray(q.tags);
    const tagsAny             = parseCsvToArray(q.tags_any);
    const awardsProviders     = q.awards ? q.awards.split(',').map(s => s.trim()).filter(Boolean).map(s => s.toLowerCase()) : null;
    const districtSlugs       = q.district_slug      ? [String(q.district_slug)]      : null;
    const neighbourhoodSlugs  = q.neighbourhood_slug ? [String(q.neighbourhood_slug)] : null;
    
    // Convertir le prix 1-4 en entier pour la RPC facets
    let priceNum = null;
    if (q.price) {
      const parsed = parseInt(String(q.price), 10);
      if (parsed >= 1 && parsed <= 4) {
        priceNum = parsed;
      }
    }
    
    const awarded             = parseBoolTriState(q.awarded);
    const fresh               = parseBoolTriState(q.fresh);

    const rpcParams = {
      p_city_slug:           q.city || 'paris',
      p_categories:          categories,
      p_subcategories:       subcategories,
      p_price:               Number.isInteger(priceNum) ? priceNum : null, // 1..4
      p_district_slugs:      districtSlugs,
      p_neighbourhood_slugs: neighbourhoodSlugs,
      p_tags_all:            tagsAll,
      p_tags_any:            tagsAny,
      p_awarded:             awarded,    // null/true/false
      p_fresh:               fresh,      // null/true/false
      p_lang:                q.lang || 'fr'
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