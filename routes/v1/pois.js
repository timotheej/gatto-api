import { LRUCache } from 'lru-cache';
import {
  PoisQuerySchema,
  PoiDetailParamsSchema,
  PoiDetailQuerySchema,
  formatZodErrors
} from '../../utils/validation.js';

// ==== CACHE CONFIGURATION ====

// LRU cache for POI responses (5 minutes TTL, max 500 entries)
const poisCache = new LRUCache({
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

// Blacklisted domains for legal reasons (trademark protection)
// Only the most litigious brands to avoid legal issues
const FAVICON_BRAND_KEYWORDS = ['michelin', 'gaultmillau', 'gault-millau'];

// Check if domain should use default favicon instead of brand favicon
function shouldUseDefaultFavicon(domain) {
  if (!domain) return false;
  const lowerDomain = domain.toLowerCase();
  return FAVICON_BRAND_KEYWORDS.some(keyword => lowerDomain.includes(keyword));
}

// ==== GATTO METADATA SYSTEM ====

// Tagline pools for deterministic variation (avoid repetition)
const TAGLINE_POOLS = {
  reference: [
    { fr: 'Référence dans sa catégorie', en: 'Category reference' },
    { fr: 'Parmi les meilleures adresses', en: 'Among the best addresses' },
    { fr: 'Incontournable de sa catégorie', en: 'Must-visit in its category' },
    { fr: 'Un des meilleurs choix', en: 'One of the best choices' }
  ],
  excellent: [
    { fr: 'Excellent choix dans sa catégorie', en: 'Excellent choice in its category' },
    { fr: 'Valeur sûre, régulièrement recommandé', en: 'Reliable choice, regularly recommended' },
    { fr: 'Parmi les bonnes adresses', en: 'Among the good addresses' },
    { fr: 'Très bon choix', en: 'Very good choice' }
  ],
  good: [
    { fr: 'Bon choix dans sa catégorie', en: 'Good choice in its category' },
    { fr: 'Option solide', en: 'Solid option' },
    { fr: 'Adresse fiable', en: 'Reliable address' },
    { fr: 'Bien noté', en: 'Well-rated' }
  ]
};

// Generate Gatto metadata (badge + tagline) from percentile
function getGattoMetadata(percentile, categoryCount, poiId, freshBonus, lang = 'fr') {
  // Skip if category too small (not enough data for meaningful percentile)
  if (categoryCount < 5) {
    return { badge: null, tagline: null, percentile: null };
  }

  // Determine level and badge based on percentile
  let level, badgeFr, badgeEn;

  if (percentile <= 10) {
    level = 'reference';
    badgeFr = 'Référence';
    badgeEn = 'Reference';
  } else if (percentile <= 25) {
    level = 'excellent';
    badgeFr = 'Excellent';
    badgeEn = 'Excellent';
  } else if (percentile <= 40) {
    level = 'good';
    badgeFr = 'Valeur sûre';
    badgeEn = 'Solid choice';
  } else if (percentile <= 60) {
    level = 'good';
    badgeFr = 'Bon choix';
    badgeEn = 'Good choice';
  } else {
    // Bottom 40%: no badge, or "fresh" badge if recent activity
    if (freshBonus > 5) {
      return {
        badge: lang === 'fr' ? 'À suivre' : 'Up & coming',
        tagline: lang === 'fr' ? 'Nouvelle adresse à suivre' : 'New address to watch',
        percentile: Math.round(percentile)
      };
    }
    return { badge: null, tagline: null, percentile: null };
  }

  // Select tagline deterministically (hash-based rotation for consistency)
  const pool = TAGLINE_POOLS[level];
  const hash = poiId.split('-')[0].charCodeAt(0) % pool.length;
  const baseTagline = pool[hash];

  // Format tagline with percentile in requested language
  const badge = lang === 'fr' ? badgeFr : badgeEn;
  const tagline = lang === 'fr'
    ? `${baseTagline.fr} · Top ${Math.round(percentile)}%`
    : `${baseTagline.en} · Top ${Math.round(percentile)}%`;

  return {
    badge,
    tagline,
    percentile: Math.round(percentile)
  };
}

// Parse CSV string to array of lowercase strings
const toArr = (v) => v ? v.split(',').map(s => s.trim()).filter(Boolean).map(s => s.toLowerCase()) : null;

const parsePriceBound = (value) => {
  if (value === undefined || value === null) return null;
  const parsed = parseInt(String(value), 10);
  if (Number.isNaN(parsed)) return null;
  if (parsed < 1 || parsed > 4) return null;
  return parsed;
};

const parseRatingBound = (value) => {
  if (value === undefined || value === null) return null;
  const parsed = Number.parseFloat(String(value));
  if (Number.isNaN(parsed)) return null;
  if (parsed < 0 || parsed > 5) return null;
  return parsed;
};

// Multi-language field picker with fallback
function pickLang(obj, lang, base) {
  const primary = obj[`${base}_${lang}`];
  const fallback = lang === 'fr' ? obj[`${base}_en`] : obj[`${base}_fr`];
  const legacy = obj[base];

  return primary || fallback || legacy || null;
}

// Parse bbox string to array
function parseBbox(str) {
  if (!str || typeof str !== 'string') return null;
  const coords = str.split(',').map(s => Number.parseFloat(s.trim())).filter(n => !Number.isNaN(n));
  if (coords.length !== 4) return null;
  const [lat_min, lng_min, lat_max, lng_max] = coords;
  // Basic validation
  if (lat_min >= lat_max || lng_min >= lng_max) return null;
  if (lat_min < -90 || lat_max > 90 || lng_min < -180 || lng_max > 180) return null;
  return [lat_min, lng_min, lat_max, lng_max];
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

// ==== ROUTES ====

export default async function poisRoutes(fastify) {

  // GET /v1/pois - Map + List view (optimized, no cursor pagination)
  fastify.get('/pois', async (request, reply) => {
    try {
      // Validate query parameters with Zod
      const validatedQuery = PoisQuerySchema.parse(request.query);

      const lang = validatedQuery.lang || fastify.getLang(request);

      const {
        bbox,
        city,
        primary_type,
        subcategory,
        neighbourhood_slug,
        district_slug,
        tags,
        tags_any,
        awards,
        awarded,
        fresh,
        price,
        price_min,
        price_max,
        rating_min,
        rating_max,
        sort,
        limit,
        page
      } = validatedQuery;

      // Parse bbox if provided (optional)
      const bboxArray = bbox ? parseBbox(bbox) : null;

      // Priority logic: if bbox provided, ignore city for RPC (but keep for cache key)
      const cityParam = bboxArray ? null : city;

      // Check cache (include both bbox and city in key)
      const cacheKey = getCacheKey('pois', {
        bbox: bboxArray ? bboxArray.join(',') : undefined,
        city: city || undefined,
        primary_type,
        subcategory,
        neighbourhood_slug,
        district_slug,
        tags,
        tags_any,
        awards,
        awarded,
        fresh,
        price,
        price_min,
        price_max,
        rating_min,
        rating_max,
        sort,
        limit,
        page,
        lang
      });

      const cached = poisCache.get(cacheKey);
      if (cached) {
        fastify.log.info({ cacheKey, endpoint: '/v1/pois' }, 'Cache HIT');
        reply.header('X-Cache', 'HIT');
        reply.header('Cache-Control', 'public, max-age=600');
        return reply.send(cached);
      }

      fastify.log.info({ cacheKey, endpoint: '/v1/pois' }, 'Cache MISS');

      // Parse parameters (limit and page are already validated by Zod)
      const primaryTypes = toArr(primary_type);
      const subcategories = toArr(subcategory);
      const districtSlugs = toArr(district_slug);
      const neighbourhoodSlugs = toArr(neighbourhood_slug);
      const tagsAll = toArr(tags);
      const tagsAny = toArr(tags_any);
      const awardsProviders = toArr(awards);

      const isAwarded = awarded === 'true' ? true : (awarded === 'false' ? false : null);
      const isFresh = fresh === 'true' ? true : (fresh === 'false' ? false : null);

      // Price bounds
      let priceMinBound = parsePriceBound(price_min);
      let priceMaxBound = parsePriceBound(price_max);
      const legacyPrice = parsePriceBound(price);
      if (legacyPrice !== null) {
        priceMinBound = priceMinBound ?? legacyPrice;
        priceMaxBound = priceMaxBound ?? legacyPrice;
      }
      if (priceMinBound !== null && priceMaxBound !== null && priceMinBound > priceMaxBound) {
        [priceMinBound, priceMaxBound] = [priceMaxBound, priceMinBound];
      }

      // Rating bounds
      let ratingMinBound = parseRatingBound(rating_min);
      let ratingMaxBound = parseRatingBound(rating_max);
      if (ratingMinBound !== null && ratingMaxBound !== null && ratingMinBound > ratingMaxBound) {
        [ratingMinBound, ratingMaxBound] = [ratingMaxBound, ratingMinBound];
      }

      // Call optimized RPC with pagination
      // Priority: bbox overrides city (cityParam is null if bbox provided)
      const { data: rows, error } = await fastify.supabase.rpc('list_pois', {
        p_bbox: bboxArray,
        p_city_slug: cityParam,
        p_primary_types: primaryTypes,
        p_subcategories: subcategories,
        p_neighbourhood_slugs: neighbourhoodSlugs,
        p_district_slugs: districtSlugs,
        p_tags_all: tagsAll,
        p_tags_any: tagsAny,
        p_awards_providers: awardsProviders,
        p_price_min: priceMinBound,
        p_price_max: priceMaxBound,
        p_rating_min: ratingMinBound,
        p_rating_max: ratingMaxBound,
        p_awarded: isAwarded,
        p_fresh: isFresh,
        p_sort: sort,
        p_limit: limit,
        p_page: page
      });

      if (error) {
        fastify.log.error('RPC list_pois error:', error);
        return reply.code(500).send({
          success: false,
          error: 'Failed to fetch POIs',
          timestamp: new Date().toISOString()
        });
      }

      const pois = rows || [];

      // Extract total_count from first row (all rows have the same value)
      const totalCount = pois.length > 0 ? Number(pois[0].total_count) : 0;

      const poiIds = pois.map(p => p.id);

      // Enrich with photos (card variants only)
      const photosData = await enrichWithPhotos(fastify, poiIds, ['card_sq']);

      // Build response items (with Gatto metadata)
      const items = await Promise.all(pois.map(async poi => {
        // Primary photo
        const poiPhotos = photosData.photos[poi.id] || [];
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
        if (poi.mentions_sample) {
          try {
            const samples = typeof poi.mentions_sample === 'string'
              ? JSON.parse(poi.mentions_sample)
              : poi.mentions_sample;
            mentionsSample = samples.map(m => ({
              domain: m.domain,
              favicon: shouldUseDefaultFavicon(m.domain)
                ? `https://www.google.com/s2/favicons?domain=example.com&sz=64`
                : `https://www.google.com/s2/favicons?domain=${m.domain}&sz=64`,
              url: m.url,
              title: m.title
            }));
          } catch (e) {
            fastify.log.error('Failed to parse mentions_sample:', e);
          }
        }

        // Fetch Gatto metadata (percentile + badge/tagline)
        let gattoMetadata = { badge: null, tagline: null, percentile: null };
        if (poi.primary_type && poi.city_slug) {
          try {
            const { data: percentileData } = await fastify.supabase.rpc(
              'get_poi_percentile_by_context',
              {
                p_poi_id: poi.id,
                p_primary_type: poi.primary_type,
                p_city_slug: poi.city_slug
              }
            );

            if (percentileData && percentileData.length > 0) {
              const { percentile, category_count } = percentileData[0];
              gattoMetadata = getGattoMetadata(
                percentile,
                category_count,
                poi.id,
                poi.freshness_bonus || 0,
                lang
              );
            }
          } catch (e) {
            fastify.log.error('Failed to fetch Gatto metadata:', e);
          }
        }

        return {
          id: poi.id,
          slug: pickLang(poi, lang, 'slug'),
          name: pickLang(poi, lang, 'name'),
          primary_type: poi.primary_type,
          subcategories: poi.subcategories || [],
          district: poi.district_slug,
          neighbourhood: poi.neighbourhood_slug,
          coords: {
            lat: Number(poi.lat),
            lng: Number(poi.lng)
          },
          photo,
          price_level: poi.price_level,
          // Gatto metadata (percentile-based badge and tagline)
          gatto_metadata: gattoMetadata,
          // Note: Gatto score is kept private (not exposed in API)
          rating: {
            google: Number(poi.rating_value || 0),
            reviews_count: poi.rating_reviews_count || 0
          },
          mentions_count: poi.mentions_count || 0,
          mentions_sample: mentionsSample,
          tags_flat: poi.tags_flat || []
        };
      }));

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
      poisCache.set(cacheKey, response);

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
      fastify.log.error('GET /pois error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });

  // GET /v1/pois/:slug - POI detail view
  fastify.get('/pois/:slug', async (request, reply) => {
    try {
      // Validate path and query parameters with Zod
      const validatedParams = PoiDetailParamsSchema.parse(request.params);
      const validatedQuery = PoiDetailQuerySchema.parse(request.query);

      const { slug } = validatedParams;
      const lang = validatedQuery.lang || fastify.getLang(request);

      // Check cache
      const cacheKey = getCacheKey('poi-detail', { slug, lang });
      const cached = poisCache.get(cacheKey);
      if (cached) {
        fastify.log.info({ cacheKey, endpoint: '/v1/pois/:slug' }, 'Cache HIT');
        reply.header('X-Cache', 'HIT');
        reply.header('Cache-Control', 'public, max-age=600');
        return reply.send(cached);
      }

      fastify.log.info({ cacheKey, endpoint: '/v1/pois/:slug' }, 'Cache MISS');

      // Fetch POI by slug (support both language variants)
      const { data: poi, error: poiError } = await fastify.supabase
        .from('poi')
        .select('*')
        .eq('publishable_status', 'eligible')
        .or(`slug_${lang}.eq.${slug},slug_en.eq.${slug},slug_fr.eq.${slug}`)
        .single();

      if (poiError || !poi) {
        return reply.code(404).send({
          success: false,
          error: 'POI not found',
          timestamp: new Date().toISOString()
        });
      }

      const poiId = poi.id;

      // Parallel fetch: scores, rating, photos, mentions, tags, percentile
      const [
        { data: scores },
        { data: rating },
        photosData,
        { data: mentions },
        { data: enrichedTags },
        { data: percentileData }
      ] = await Promise.all([
        // Scores
        fastify.supabase
          .from('latest_gatto_scores')
          .select('poi_id, gatto_score, digital_score, awards_bonus, freshness_bonus, calculated_at')
          .eq('poi_id', poiId)
          .single(),

        // Rating
        fastify.supabase
          .from('latest_google_rating')
          .select('poi_id, rating_value, reviews_count')
          .eq('poi_id', poiId)
          .single(),

        // Photos with all variants
        enrichWithPhotos(fastify, [poiId], ['card_sq', 'detail', 'thumb_small']),

        // Mentions (with details)
        fastify.supabase
          .from('ai_mention')
          .select('domain, title, excerpt, url, published_at_guess, last_seen_at')
          .eq('poi_id', poiId)
          .eq('ai_decision', 'ACCEPT')
          .order('published_at_guess', { ascending: false }),

        // Tags enrichment
        fastify.supabase.rpc('enrich_tags_with_labels', {
          p_tags: poi.tags,
          p_lang: lang
        }),

        // Percentile for Gatto metadata
        fastify.supabase.rpc('get_poi_percentile_by_context', {
          p_poi_id: poiId,
          p_primary_type: poi.primary_type,
          p_city_slug: poi.city_slug
        })
      ]);

      // Build photo blocks
      const poiPhotos = photosData.photos[poiId] || [];
      const primaryPhoto = poiPhotos.find(p => p.is_primary) || poiPhotos[0];

      let photosPrimary = null;
      let photosGallery = [];

      if (primaryPhoto) {
        const primaryBlock = photoBlockFrom(photosData.variants, primaryPhoto, 'detail');
        const primaryCard = photoBlockFrom(photosData.variants, primaryPhoto, 'card_sq');

        if (primaryBlock) {
          photosPrimary = {
            variants: primaryBlock.variants,
            dominant_color: primaryBlock.dominant_color,
            blurhash: primaryBlock.blurhash,
            card: primaryCard ? {
              variants: primaryCard.variants,
              dominant_color: primaryCard.dominant_color,
              blurhash: primaryCard.blurhash
            } : null
          };
        }
      }

      // Gallery (up to 5 additional photos)
      const galleryPhotos = poiPhotos.filter(p => p.id !== primaryPhoto?.id).slice(0, 5);
      photosGallery = galleryPhotos
        .map(photo => photoBlockFrom(photosData.variants, photo, 'detail'))
        .filter(Boolean);

      // Mentions sample
      const mentionsSample = (mentions || []).map(m => ({
        domain: m.domain,
        favicon: shouldUseDefaultFavicon(m.domain)
          ? `https://www.google.com/s2/favicons?domain=example.com&sz=64`
          : `https://www.google.com/s2/favicons?domain=${m.domain}&sz=64`,
        title: m.title,
        excerpt: m.excerpt,
        url: m.url,
        published_at: m.published_at_guess
      }));

      // Parse awards from JSONB column
      let awards = [];
      if (poi.awards) {
        try {
          awards = typeof poi.awards === 'string'
            ? JSON.parse(poi.awards)
            : poi.awards;
          // Ensure it's an array
          if (!Array.isArray(awards)) {
            awards = [];
          }
        } catch (e) {
          fastify.log.error('Failed to parse awards:', e);
          awards = [];
        }
      }

      // Generate Gatto metadata from percentile
      let gattoMetadata = { badge: null, tagline: null, percentile: null };
      if (percentileData && percentileData.length > 0) {
        const { percentile, category_count } = percentileData[0];
        gattoMetadata = getGattoMetadata(
          percentile,
          category_count,
          poi.id,
          scores?.freshness_bonus || 0,
          lang
        );
      }

      // Build response
      const response = {
        id: poi.id,
        slug: pickLang(poi, lang, 'slug'),
        name: pickLang(poi, lang, 'name'),
        primary_type: poi.primary_type,
        city: poi.city,
        district: poi.district_slug,
        neighbourhood: poi.neighbourhood_slug,
        coords: { lat: Number(poi.lat), lng: Number(poi.lng) },
        price_level: poi.price_level,
        tags_keys: poi.tags,
        tags: enrichedTags || [],
        awards,
        summary: pickLang(poi, lang, 'ai_summary'),
        opening_hours: poi.opening_hours,
        google_place_id: poi.google_place_id,
        address: poi.address_street,
        website: poi.website,
        phone: poi.phone,
        photos: {
          primary: photosPrimary,
          gallery: photosGallery
        },
        // Gatto metadata (percentile-based badge and tagline)
        gatto_metadata: gattoMetadata,
        // Note: Gatto score is kept private (not exposed in API)
        rating: {
          google: Number(rating?.rating_value || 0),
          reviews_count: rating?.reviews_count || 0
        },
        mentions_count: mentionsSample.length,
        mentions_sample: mentionsSample
      };

      // Build final response
      const finalResponse = {
        success: true,
        data: response,
        timestamp: new Date().toISOString()
      };

      // Store in cache
      poisCache.set(cacheKey, finalResponse);

      // Send response
      reply.header('X-Cache', 'MISS');
      reply.header('Cache-Control', 'public, max-age=600');
      return reply.send(finalResponse);

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
      fastify.log.error('GET /pois/:slug error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });
}
