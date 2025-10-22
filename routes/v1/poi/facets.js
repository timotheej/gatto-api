import { z } from "zod";

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

function parseSingleFromCsv(str, { lowercase = false } = {}) {
  const arr = parseCsvToArray(str, { lowercase });
  return arr?.[0] ?? null;
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

// Validation schema
const QuerySchema = z
  .object({
    city: z.string().default("paris"),
    district_slug: z.string().optional(),
    neighbourhood_slug: z.string().optional(),
    primary_type: z.string().optional(),
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
    lang: z.string().optional(),
    bbox: z.string().optional(), // Format: "lat_min,lng_min,lat_max,lng_max"
  })
  .strict();

/**
 * Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).
 */
export default async function poiFacetsRoutes(fastify) {
  fastify.get(
    "/v1/poi/facets",
    {
      schema: {
        description:
          "Facettes contextuelles pour les POI (ville/arrondissement/quartier + filtres).",
        tags: ["POI"],
      },
    },
    async (request, reply) => {
      // 1) Parse & validate
      const parsed = QuerySchema.safeParse(request.query);
      if (!parsed.success) {
        return reply.code(400).send({ success: false, error: "Invalid query" });
      }

      const q = request.query || {};

      const primaryTypes = uniq(
        parseCsvToArray(q.primary_type, { lowercase: true })
      );
      const subcategories = uniq(
        parseCsvToArray(q.subcategory, { lowercase: true })
      );
      const tagsAll = uniq(parseCsvToArray(q.tags, { lowercase: true }));
      const tagsAny = uniq(parseCsvToArray(q.tags_any, { lowercase: true }));
      const awardsProviders = uniq(
        parseCsvToArray(q.awards, { lowercase: true })
      );
      const districtSlugs = uniq(
        parseCsvToArray(q.district_slug, { lowercase: true })
      );
      const neighbourhoodSlugs = uniq(
        parseCsvToArray(q.neighbourhood_slug, { lowercase: true })
      );
      const bbox = parseBbox(q.bbox);
      let priceMin = parsePriceBound(q.price_min);
      let priceMax = parsePriceBound(q.price_max);
      const ratingMin = parseRatingBound(q.rating_min);
      const ratingMax = parseRatingBound(q.rating_max);

      // Compat: legacy single price maps to exact range
      const legacyPrice = parsePriceBound(q.price);
      if (legacyPrice !== null) {
        priceMin = priceMin ?? legacyPrice;
        priceMax = priceMax ?? legacyPrice;
      }

      const awarded = parseBoolTriState(q.awarded);
      const fresh = parseBoolTriState(q.fresh);

      // Sort validation
      const allowedSort = new Set([
        "gatto",
        "rating",
        "mentions",
        "price_asc",
        "price_desc",
      ]);
      const sort = allowedSort.has(q.sort) ? q.sort : "gatto";

      const rpcParams = {
        p_city_slug: q.city || "paris",
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
        p_sort: sort,
        p_lang: q.lang === "fr" || q.lang === "en" ? q.lang : "fr",
      };

      // Appel RPC
      try {
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
            .send({ success: false, error: "Failed to compute facets" });
        }

        // La RPC renvoie déjà le format JSON correct { context, facets }
        const payload = data;

        // Réponse HTTP (cache aligné sur /v1/poi)
        reply.header("Cache-Control", "public, max-age=300");
        return reply.send({ success: true, data: payload });
      } catch (e) {
        request.log.error(
          { rpc: "rpc_get_pois_facets", e, rpcParams },
          "Exception in RPC facets"
        );
        return reply
          .code(500)
          .send({ success: false, error: "Failed to compute facets" });
      }
    }
  );
}
