import { z } from 'zod';

// Helpers from poi.js
const capFromSlug = (s) => s
  ? s.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
  : null;

// Price mapping
const PRICE_MAP = {
  '€': 'PRICE_LEVEL_INEXPENSIVE',
  '€€': 'PRICE_LEVEL_MODERATE',
  '€€€': 'PRICE_LEVEL_EXPENSIVE',
  '€€€€': 'PRICE_LEVEL_VERY_EXPENSIVE'
};

// Validation schema
const QuerySchema = z.object({
  city: z.string().default('paris'),
  district_slug: z.string().optional(),
  neighbourhood_slug: z.string().optional(),
  category: z.string().optional(),
  price: z.string().optional(),
  tags: z.string().optional(),
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
    
    const { city, district_slug, neighbourhood_slug, category, price, tags, lang: qLang } = parsed.data;

    // 2) Lang detection
    const lang = qLang || (request.headers['accept-language']?.toString().startsWith('en') ? 'en' : 'fr');

    // 3) Slug -> name conversion
    const districtName = capFromSlug(district_slug);
    const neighbourhoodName = capFromSlug(neighbourhood_slug);

    // 4) Price mapping (if needed)
    const priceEnum = price ? (PRICE_MAP[price] || price) : null;

    // 5) RPC call
    const { data, error } = await fastify.supabase.rpc('rpc_get_poi_facets', {
      p_city_slug: city,
      p_district_name: districtName,
      p_neighbourhood: neighbourhoodName,
      p_category: category ?? null,
      p_price_level: priceEnum ?? null,
      p_tags_all_csv: tags ?? null,
      p_lang: lang
    });

    if (error) {
      request.log.error(error);
      return reply.code(500).send({ success: false, error: error.message });
    }

    if (!data) {
      return reply.code(404).send({ success: false, error: 'No data' });
    }

    // Return standardized structure
    return reply.send({
      success: true,
      data: {
        context: { 
          city, 
          total_results: data.total_results ?? 0 
        },
        facets: data.facets ?? { 
          category: [], 
          subcategories: [], 
          price: [], 
          tags: [] 
        }
      }
    });
  });
}