import {
  PoisFacetsQuerySchema,
  formatZodErrors
} from '../../../utils/validation.js';

// Utility functions for parameter parsing
function parseCsvToArray(str, { lowercase = false } = {}) {
  if (!str || typeof str !== "string") return null;
  const arr = str
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => (lowercase ? s.toLowerCase() : s));
  return arr.length ? arr : null;
}

function uniq(arr) {
  return Array.isArray(arr) ? [...new Set(arr)] : null;
}

function parseBoolTriState(v) {
  if (typeof v === "boolean") return v;
  if (typeof v !== "string") return null;
  if (v === "true") return true;
  if (v === "false") return false;
  return null;
}

function parseBbox(str) {
  if (!str || typeof str !== "string") return null;
  const coords = str
    .split(",")
    .map((s) => Number.parseFloat(s.trim()))
    .filter((n) => !Number.isNaN(n));
  if (coords.length !== 4) return null;
  const [lat_min, lng_min, lat_max, lng_max] = coords;
  // Basic validation
  if (lat_min >= lat_max || lng_min >= lng_max) return null;
  if (lat_min < -90 || lat_max > 90 || lng_min < -180 || lng_max > 180)
    return null;
  return [lat_min, lng_min, lat_max, lng_max];
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

/**
 * Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).
 */
export default async function poisFacetsRoutes(fastify) {
  fastify.get(
    "/v1/pois/facets",
    {
      schema: {
        description:
          "Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).",
        tags: ["POI"],
      },
    },
    async (request, reply) => {
      try {
        // 1) Validate query parameters with Zod
        const validatedQuery = PoisFacetsQuerySchema.parse(request.query);

        const primaryTypes = uniq(
          parseCsvToArray(validatedQuery.primary_type, { lowercase: true })
        );
        const subcategories = uniq(
          parseCsvToArray(validatedQuery.subcategory, { lowercase: true })
        );
        const tagsAll = uniq(parseCsvToArray(validatedQuery.tags, { lowercase: true }));
        const tagsAny = uniq(parseCsvToArray(validatedQuery.tags_any, { lowercase: true }));
        const awardsProviders = uniq(
          parseCsvToArray(validatedQuery.awards, { lowercase: true })
        );
        const districtSlugs = uniq(
          parseCsvToArray(validatedQuery.district_slug, { lowercase: true })
        );
        const neighbourhoodSlugs = uniq(
          parseCsvToArray(validatedQuery.neighbourhood_slug, { lowercase: true })
        );
        const bbox = parseBbox(validatedQuery.bbox);
        let priceMin = parsePriceBound(validatedQuery.price_min);
        let priceMax = parsePriceBound(validatedQuery.price_max);
        const ratingMin = parseRatingBound(validatedQuery.rating_min);
        const ratingMax = parseRatingBound(validatedQuery.rating_max);

        // Compat: legacy single price maps to exact range
        const legacyPrice = parsePriceBound(validatedQuery.price);
        if (legacyPrice !== null) {
          priceMin = priceMin ?? legacyPrice;
          priceMax = priceMax ?? legacyPrice;
        }

        const awarded = parseBoolTriState(validatedQuery.awarded);
        const fresh = parseBoolTriState(validatedQuery.fresh);

        const rpcParams = {
          p_city_slug: validatedQuery.city,
          p_primary_types: primaryTypes ?? null,
          p_subcategories: subcategories ?? null,
          p_district_slugs: districtSlugs ?? null,
          p_neighbourhood_slugs: neighbourhoodSlugs ?? null,
          p_tags_all: tagsAll ?? null,
          p_tags_any: tagsAny ?? null,
          p_awards_providers: awardsProviders ?? null,
          p_price_min: priceMin ?? null,
          p_price_max: priceMax ?? null,
          p_rating_min: ratingMin ?? null,
          p_rating_max: ratingMax ?? null,
          p_bbox: bbox ?? null,
          p_awarded: awarded, // null/true/false
          p_fresh: fresh, // null/true/false
          p_sort: validatedQuery.sort
        };

        // Appel RPC
        const { data, error } = await fastify.supabase.rpc(
          "rpc_get_pois_facets",
          rpcParams
        );
        if (error) {
          request.log.error(
            { rpc: "rpc_get_pois_facets", error, rpcParams },
            "RPC facets failed"
          );
          return reply
            .code(500)
            .send({
              success: false,
              error: "Failed to compute facets",
              timestamp: new Date().toISOString()
            });
        }

        // La RPC renvoie déjà le format JSON correct { context, facets }
        const payload = data;

        // Réponse HTTP (cache 10min, aligné sur /v1/pois)
        reply.header("Cache-Control", "public, max-age=600");
        return reply.send({
          success: true,
          data: payload,
          timestamp: new Date().toISOString()
        });

      } catch (err) {
        // Handle Zod validation errors
        if (err.name === 'ZodError') {
          return reply.code(400).send({
            success: false,
            error: 'Invalid query parameters',
            details: formatZodErrors(err),
            timestamp: new Date().toISOString()
          });
        }

        // Handle other errors
        request.log.error('GET /v1/pois/facets error:', err);
        return reply.code(500).send({
          success: false,
          error: 'Internal server error',
          timestamp: new Date().toISOString()
        });
      }
    }
  );
}
