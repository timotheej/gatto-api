// ==== HELPERS ====

// Clamp value between min and max
function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

// Convert 0-100 Gatto score to 0-5 scale
function convertScoreTo5Scale(score100) {
  // Handle null/undefined
  if (score100 == null) {
    return 0;
  }

  // Convert to number (handles both numbers and numeric strings from Supabase)
  const scoreNum =
    typeof score100 === "number" ? score100 : parseFloat(score100);

  // Validate it's a valid number
  if (!Number.isFinite(scoreNum)) {
    return 0;
  }

  const score05 = scoreNum / 20;
  return Number(clamp(score05, 0, 5).toFixed(2));
}

// ==== ROUTES ====

export default async function sitemapRoutes(fastify) {
  // GET /v1/sitemap/pois - Paginated list for sitemap builder
  fastify.get("/sitemap/pois", async (request, reply) => {
    try {
      // --- 1) Parse & validate pagination params ---
      const pageRaw = request.query.page;
      const limitRaw = request.query.limit;

      const page =
        Number.isFinite(Number(pageRaw)) && Number(pageRaw) >= 1
          ? Number(pageRaw)
          : 1;

      const LIMIT_MAX = 1000;
      const LIMIT_DEFAULT = 500;
      let limit =
        Number.isFinite(Number(limitRaw)) && Number(limitRaw) >= 1
          ? Number(limitRaw)
          : LIMIT_DEFAULT;

      if (limit > LIMIT_MAX) limit = LIMIT_MAX;

      const offset = (page - 1) * limit;

      // --- 2) Fetch eligible POIs (paginated) ---
      const {
        data: pois,
        count,
        error: poiError,
      } = await fastify.supabase
        .from("poi")
        .select("id, slug_fr, slug_en, updated_at, publishable_status", {
          count: "exact",
        })
        .eq("publishable_status", "eligible")
        .order("updated_at", { ascending: false })
        .range(offset, offset + limit - 1);

      if (poiError) {
        fastify.log.error(
          { error: poiError },
          "Failed to fetch POIs for sitemap"
        );
        return reply.error("Failed to build sitemap payload", 500);
      }

      // Handle empty result early
      if (!pois || pois.length === 0) {
        reply.header("Cache-Control", "public, max-age=300");
        return reply.success({
          items: [],
          pagination: {
            total: count ?? 0,
            page,
            limit,
            has_next: false,
          },
        });
      }

      const ids = pois.map((p) => p.id);

      // --- 3) Fetch latest scores in bulk (with batching for large requests) ---
      // PostgREST has URL length limits, so we batch the .in() queries
      const BATCH_SIZE = 100;
      const allScores = [];

      for (let i = 0; i < ids.length; i += BATCH_SIZE) {
        const batchIds = ids.slice(i, i + BATCH_SIZE);
        const { data: batchScores, error: scoresError } = await fastify.supabase
          .from("latest_gatto_scores")
          .select("poi_id, gatto_score")
          .in("poi_id", batchIds);

        if (scoresError) {
          fastify.log.warn(
            { error: scoresError, batch: i / BATCH_SIZE + 1 },
            "Failed to fetch scores batch for sitemap, continuing with defaults"
          );
        } else if (batchScores) {
          allScores.push(...batchScores);
        }
      }

      // Build score map for O(1) lookup
      const scoreById = new Map(
        allScores.map((s) => [s.poi_id, s.gatto_score])
      );

      // --- 4) Build response items (score 0–5 expected by sitemap builder) ---
      const items = pois.map((p) => {
        const slug = p.slug_fr || p.slug_en;
        const gattoScore100 = scoreById.get(p.id);
        const score = convertScoreTo5Scale(gattoScore100);

        return {
          slug,
          updated_at: p.updated_at,
          score,
        };
      });

      const total = count ?? items.length;
      const has_next = offset + items.length < total;

      // --- 5) Set caching headers ---
      reply.header("Cache-Control", "public, max-age=300");

      return reply.success({
        items,
        pagination: {
          total,
          page,
          limit,
          has_next,
        },
      });
    } catch (err) {
      fastify.log.error({ err }, "GET /v1/sitemap/pois failed");
      return reply.error("Failed to build sitemap payload", 500);
    }
  });
}
