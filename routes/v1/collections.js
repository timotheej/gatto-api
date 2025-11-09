import { LRUCache } from 'lru-cache';
import {
  CollectionsQuerySchema,
  CollectionDetailParamsSchema,
  CollectionDetailQuerySchema,
  formatZodErrors
} from '../../utils/validation.js';

// ==== CACHE CONFIGURATION ====

// LRU cache for collections responses (5 minutes TTL, max 500 entries)
const collectionsCache = new LRUCache({
  max: 500,               // Max 500 entries
  ttl: 1000 * 60 * 5,     // 5 minutes TTL
  updateAgeOnGet: true,   // Reset TTL on cache hit
  updateAgeOnHas: false
});

// Generate stable cache key from params
function getCacheKey(prefix, params) {
  const sortedParams = Object.keys(params)
    .sort()
    .reduce((acc, key) => {
      if (params[key] !== undefined && params[key] !== null) {
        acc[key] = Array.isArray(params[key]) ? params[key].join(',') : params[key];
      }
      return acc;
    }, {});
  return `${prefix}:${JSON.stringify(sortedParams)}`;
}

// ==== HELPERS ====

// Multi-language field picker with fallback
function pickLang(obj, lang, base) {
  const primary = obj[`${base}_${lang}`];
  const fallback = lang === 'fr' ? obj[`${base}_en`] : obj[`${base}_fr`];
  const legacy = obj[base];

  return primary || fallback || legacy || null;
}

// ==== Image variant helpers ====
function photoBlockFrom(variantsIndex, photo, wantedKeyPrefix) {
  const photoVariants = variantsIndex[photo.id] || [];

  const variants = photoVariants
    .filter(v => v.variant_key.startsWith(wantedKeyPrefix))
    .sort((a, b) => {
      const keyA = a.variant_key;
      const keyB = b.variant_key;
      if (keyA !== keyB) {
        return keyA.localeCompare(keyB);
      }
      return ['avif', 'webp', 'jpg'].indexOf(a.format) - ['avif', 'webp', 'jpg'].indexOf(b.format);
    })
    .map(v => ({
      variant_key: v.variant_key,
      format: v.format,
      url: v.cdn_url,
      width: v.width,
      height: v.height
    }));

  if (variants.length) {
    return {
      variants,
      width: photo.width || (variants[0] && variants[0].width) || null,
      height: photo.height || (variants[0] && variants[0].height) || null,
      dominant_color: photo.dominant_color || null,
      blurhash: photo.blurhash || null,
    };
  }

  if (photo.cdn_url) {
    return {
      variants: [{ format: photo.format || 'jpg', url: photo.cdn_url, width: photo.width || null, height: photo.height || null }],
      width: photo.width || null,
      height: photo.height || null,
      dominant_color: photo.dominant_color || null,
      blurhash: photo.blurhash || null,
    };
  }

  return null;
}

// ==== BUSINESS LOGIC ====

// Enriches POIs with photos and variants (OPTIMIZED with JOIN - 2 queries → 1 query)
async function enrichWithPhotos(fastify, poiIds, variantKeys = ['card_sq']) {
  if (!poiIds.length) return { photos: {}, variants: {} };

  // Build variant keys with all density variants
  const allVariantKeys = [];
  variantKeys.forEach(key => {
    if (!key.includes('@')) {
      allVariantKeys.push(`${key}@1x`, `${key}@2x`);
    } else {
      allVariantKeys.push(key);
    }
  });

  // OPTIMIZED: Single query with JOIN (instead of 2 sequential queries)
  const { data: photosWithVariants } = await fastify.supabase
    .from('poi_photos')
    .select(`
      id,
      poi_id,
      dominant_color,
      blurhash,
      is_primary,
      width,
      height,
      cdn_url,
      format,
      position,
      poi_photo_variants!inner (
        variant_key,
        cdn_url,
        format,
        width,
        height
      )
    `)
    .in('poi_id', poiIds)
    .eq('status', 'active')
    .in('poi_photo_variants.variant_key', allVariantKeys)
    .order('is_primary', { ascending: false })
    .order('position', { ascending: true });

  if (!photosWithVariants?.length) return { photos: {}, variants: {} };

  // Organize by poi_id and photo_id
  const photosByPoi = {};
  const variantsByPhoto = {};
  const seenPhotos = new Set();

  photosWithVariants.forEach(photo => {
    // Add photo to photosByPoi (deduplicate)
    if (!seenPhotos.has(photo.id)) {
      if (!photosByPoi[photo.poi_id]) {
        photosByPoi[photo.poi_id] = [];
      }
      photosByPoi[photo.poi_id].push({
        id: photo.id,
        poi_id: photo.poi_id,
        dominant_color: photo.dominant_color,
        blurhash: photo.blurhash,
        is_primary: photo.is_primary,
        width: photo.width,
        height: photo.height,
        cdn_url: photo.cdn_url,
        format: photo.format
      });
      seenPhotos.add(photo.id);
    }

    // Add variants
    if (photo.poi_photo_variants) {
      const variants = Array.isArray(photo.poi_photo_variants)
        ? photo.poi_photo_variants
        : [photo.poi_photo_variants];

      variants.forEach(variant => {
        if (!variantsByPhoto[photo.id]) {
          variantsByPhoto[photo.id] = [];
        }
        variantsByPhoto[photo.id].push({
          photo_id: photo.id,
          variant_key: variant.variant_key,
          cdn_url: variant.cdn_url,
          format: variant.format,
          width: variant.width,
          height: variant.height
        });
      });
    }
  });

  return { photos: photosByPoi, variants: variantsByPhoto };
}

// Enriches cover photos with variants for collections
async function enrichCoverPhotos(fastify, photoIds) {
  if (!photoIds.length) return { variants: {} };

  const allVariantKeys = ['card_sq@1x', 'card_sq@2x'];

  const { data: photosWithVariants } = await fastify.supabase
    .from('poi_photos')
    .select(`
      id,
      dominant_color,
      blurhash,
      width,
      height,
      cdn_url,
      format,
      poi_photo_variants!inner (
        variant_key,
        cdn_url,
        format,
        width,
        height
      )
    `)
    .in('id', photoIds)
    .in('poi_photo_variants.variant_key', allVariantKeys);

  if (!photosWithVariants?.length) return { variants: {} };

  const variantsByPhoto = {};

  photosWithVariants.forEach(photo => {
    if (photo.poi_photo_variants) {
      const variants = Array.isArray(photo.poi_photo_variants)
        ? photo.poi_photo_variants
        : [photo.poi_photo_variants];

      variants.forEach(variant => {
        if (!variantsByPhoto[photo.id]) {
          variantsByPhoto[photo.id] = [];
        }
        variantsByPhoto[photo.id].push({
          photo_id: photo.id,
          variant_key: variant.variant_key,
          cdn_url: variant.cdn_url,
          format: variant.format,
          width: variant.width,
          height: variant.height
        });
      });
    }
  });

  return { variants: variantsByPhoto };
}

// ==== ROUTES ====

export default async function collectionsRoutes(fastify) {

  // GET /v1/collections - List collections
  fastify.get('/collections', async (request, reply) => {
    try {
      // Validate query parameters with Zod
      const validatedQuery = CollectionsQuerySchema.parse(request.query);

      const { city, lang, limit, page } = validatedQuery;

      // Check cache
      const cacheKey = getCacheKey('collections', { city, lang, limit, page });
      const cached = collectionsCache.get(cacheKey);
      if (cached) {
        fastify.log.info({ cacheKey, endpoint: '/v1/collections' }, 'Cache HIT');
        reply.header('X-Cache', 'HIT');
        reply.header('Cache-Control', 'public, max-age=600');
        return reply.send(cached);
      }

      fastify.log.info({ cacheKey, endpoint: '/v1/collections' }, 'Cache MISS');

      // Call RPC
      const { data: rows, error } = await fastify.supabase.rpc('list_collections', {
        p_city_slug: city,
        p_limit: limit,
        p_page: page
      });

      if (error) {
        fastify.log.error('RPC list_collections error:', error);
        return reply.code(500).send({
          success: false,
          error: 'Failed to fetch collections',
          timestamp: new Date().toISOString()
        });
      }

      const collections = rows || [];

      // Extract total_count from first row
      const totalCount = collections.length > 0 ? Number(collections[0].total_count) : 0;

      // Get unique photo IDs for cover photos
      const photoIds = collections
        .map(c => c.cover_photo_id)
        .filter(Boolean);

      // Enrich with photo variants
      const photosData = await enrichCoverPhotos(fastify, photoIds);

      // Build response items
      const items = collections.map(collection => {
        let coverPhoto = null;

        if (collection.cover_photo_id) {
          const photo = {
            id: collection.cover_photo_id,
            cdn_url: collection.cover_photo_cdn_url,
            format: collection.cover_photo_format,
            width: collection.cover_photo_width,
            height: collection.cover_photo_height,
            dominant_color: collection.cover_photo_dominant_color,
            blurhash: collection.cover_photo_blurhash
          };

          const block = photoBlockFrom(photosData.variants, photo, 'card_sq');
          if (block) {
            coverPhoto = {
              variants: block.variants,
              dominant_color: block.dominant_color,
              blurhash: block.blurhash
            };
          }
        }

        return {
          id: collection.id,
          slug: pickLang(collection, lang, 'slug'),
          slug_fr: collection.slug_fr,
          slug_en: collection.slug_en,
          title: pickLang(collection, lang, 'title'),
          title_fr: collection.title_fr,
          title_en: collection.title_en,
          city_slug: collection.city_slug,
          is_dynamic: collection.is_dynamic,
          rules_json: collection.rules_json,
          theme_type: collection.theme_type,
          season_window: collection.season_window,
          cover_photo: coverPhoto,
          created_at: collection.created_at,
          updated_at: collection.updated_at
        };
      });

      // Calculate pagination metadata
      const totalPages = Math.ceil(totalCount / limit);
      const hasNext = page < totalPages;
      const hasPrev = page > 1;

      // Build response with pagination
      const response = {
        success: true,
        data: {
          items,
          pagination: {
            total: totalCount,
            per_page: limit,
            current_page: page,
            total_pages: totalPages,
            has_next: hasNext,
            has_prev: hasPrev
          }
        },
        timestamp: new Date().toISOString()
      };

      // Store in cache
      collectionsCache.set(cacheKey, response);

      // Send response
      reply.header('X-Cache', 'MISS');
      reply.header('Cache-Control', 'public, max-age=600');
      return reply.send(response);

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
      fastify.log.error('GET /collections error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });

  // GET /v1/collections/:slug - Collection detail with POIs
  fastify.get('/collections/:slug', async (request, reply) => {
    try {
      // Validate path and query parameters with Zod
      const validatedParams = CollectionDetailParamsSchema.parse(request.params);
      const validatedQuery = CollectionDetailQuerySchema.parse(request.query);

      const { slug } = validatedParams;
      const { lang, limit, page } = validatedQuery;

      // Check cache
      const cacheKey = getCacheKey('collection-detail', { slug, lang, limit, page });
      const cached = collectionsCache.get(cacheKey);
      if (cached) {
        fastify.log.info({ cacheKey, endpoint: '/v1/collections/:slug' }, 'Cache HIT');
        reply.header('X-Cache', 'HIT');
        reply.header('Cache-Control', 'public, max-age=600');
        return reply.send(cached);
      }

      fastify.log.info({ cacheKey, endpoint: '/v1/collections/:slug' }, 'Cache MISS');

      // Call RPC
      const { data: rows, error } = await fastify.supabase.rpc('get_collection_pois', {
        p_slug: slug,
        p_limit: limit,
        p_page: page
      });

      if (error) {
        // Check if collection not found
        if (error.message && error.message.includes('Collection not found')) {
          return reply.code(404).send({
            success: false,
            error: 'Collection not found',
            timestamp: new Date().toISOString()
          });
        }

        fastify.log.error({ error, slug, limit, page }, 'RPC get_collection_pois error');
        return reply.code(500).send({
          success: false,
          error: 'Failed to fetch collection',
          details: error.message || error.toString(),
          timestamp: new Date().toISOString()
        });
      }

      if (!rows || rows.length === 0) {
        return reply.code(404).send({
          success: false,
          error: 'Collection not found or empty',
          timestamp: new Date().toISOString()
        });
      }

      // Extract collection info from first row (same for all rows)
      const firstRow = rows[0];
      const totalCount = Number(firstRow.total_count);

      // Build collection object
      let collectionCoverPhoto = null;
      if (firstRow.collection_cover_photo_id) {
        const photo = {
          id: firstRow.collection_cover_photo_id,
          cdn_url: firstRow.collection_cover_photo_cdn_url,
          format: firstRow.collection_cover_photo_format,
          width: firstRow.collection_cover_photo_width,
          height: firstRow.collection_cover_photo_height,
          dominant_color: firstRow.collection_cover_photo_dominant_color,
          blurhash: firstRow.collection_cover_photo_blurhash
        };

        // Enrich cover photo with variants
        const photosData = await enrichCoverPhotos(fastify, [firstRow.collection_cover_photo_id]);
        const block = photoBlockFrom(photosData.variants, photo, 'card_sq');
        if (block) {
          collectionCoverPhoto = {
            variants: block.variants,
            dominant_color: block.dominant_color,
            blurhash: block.blurhash
          };
        }
      }

      const collection = {
        id: firstRow.collection_id,
        slug: pickLang(firstRow, lang, 'collection_slug'),
        slug_fr: firstRow.collection_slug_fr,
        slug_en: firstRow.collection_slug_en,
        title: pickLang(firstRow, lang, 'collection_title'),
        title_fr: firstRow.collection_title_fr,
        title_en: firstRow.collection_title_en,
        city_slug: firstRow.collection_city_slug,
        is_dynamic: firstRow.collection_is_dynamic,
        rules_json: firstRow.collection_rules_json,
        theme_type: firstRow.collection_theme_type,
        season_window: firstRow.collection_season_window,
        cover_photo: collectionCoverPhoto,
        created_at: firstRow.collection_created_at,
        updated_at: firstRow.collection_updated_at
      };

      // Extract POI IDs
      const poiIds = rows.map(r => r.poi_id);

      // Enrich POIs with photos (card variants only)
      const photosData = await enrichWithPhotos(fastify, poiIds, ['card_sq']);

      // Build POIs array
      const pois = rows.map(row => {
        // Primary photo
        const poiPhotos = photosData.photos[row.poi_id] || [];
        const primaryPhoto = poiPhotos.find(p => p.is_primary) || poiPhotos[0];

        let photo = null;
        if (primaryPhoto) {
          const block = photoBlockFrom(photosData.variants, primaryPhoto, 'card_sq');
          if (block) {
            photo = {
              variants: block.variants,
              dominant_color: block.dominant_color,
              blurhash: block.blurhash
            };
          }
        }

        // Parse mentions_sample from JSONB
        let mentionsSample = [];
        if (row.poi_mentions_sample) {
          try {
            const samples = typeof row.poi_mentions_sample === 'string'
              ? JSON.parse(row.poi_mentions_sample)
              : row.poi_mentions_sample;
            mentionsSample = samples.map(m => ({
              domain: m.domain,
              favicon: `https://www.google.com/s2/favicons?domain=${m.domain}&sz=64`,
              url: m.url,
              title: m.title
            }));
          } catch (e) {
            fastify.log.error('Failed to parse mentions_sample:', e);
          }
        }

        return {
          id: row.poi_id,
          slug: pickLang(row, lang, 'poi_slug'),
          name: pickLang(row, lang, 'poi_name'),
          primary_type: row.poi_primary_type,
          subcategories: row.poi_subcategories || [],
          district: row.poi_district_slug,
          neighbourhood: row.poi_neighbourhood_slug,
          coords: {
            lat: Number(row.poi_lat),
            lng: Number(row.poi_lng)
          },
          photo,
          price_level: row.poi_price_level,
          score: Number(row.poi_gatto_score || 0),
          scores: {
            gatto: Number(row.poi_gatto_score || 0),
            digital: Number(row.poi_digital_score || 0),
            awards_bonus: Number(row.poi_awards_bonus || 0),
            freshness_bonus: Number(row.poi_freshness_bonus || 0)
          },
          rating: {
            google: Number(row.poi_rating_value || 0),
            reviews_count: row.poi_rating_reviews_count || 0
          },
          mentions_count: row.poi_mentions_count || 0,
          mentions_sample: mentionsSample,
          tags_flat: row.poi_tags_flat || [],
          // Collection specific fields
          collection_position: row.collection_position,
          collection_reason: row.collection_reason
        };
      });

      // Calculate pagination metadata
      const totalPages = Math.ceil(totalCount / limit);
      const hasNext = page < totalPages;
      const hasPrev = page > 1;

      // Build response
      const response = {
        success: true,
        data: {
          collection,
          pois,
          pagination: {
            total: totalCount,
            per_page: limit,
            current_page: page,
            total_pages: totalPages,
            has_next: hasNext,
            has_prev: hasPrev
          }
        },
        timestamp: new Date().toISOString()
      };

      // Store in cache
      collectionsCache.set(cacheKey, response);

      // Send response
      reply.header('X-Cache', 'MISS');
      reply.header('Cache-Control', 'public, max-age=600');
      return reply.send(response);

    } catch (err) {
      // Handle Zod validation errors
      if (err.name === 'ZodError') {
        return reply.code(400).send({
          success: false,
          error: 'Invalid parameters',
          details: formatZodErrors(err),
          timestamp: new Date().toISOString()
        });
      }

      // Handle other errors
      fastify.log.error('GET /collections/:slug error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });
}
