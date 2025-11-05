// ==== HELPERS ====

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

// Enriches POIs with photos and variants
async function enrichWithPhotos(fastify, poiIds, variantKeys = ['card_sq@1x', 'card_sq@2x']) {
  if (!poiIds.length) return { photos: {}, variants: {} };

  // Fetch photos
  const { data: photosData } = await fastify.supabase
    .from('poi_photos')
    .select('id, poi_id, dominant_color, blurhash, is_primary, width, height, cdn_url, format')
    .in('poi_id', poiIds)
    .eq('status', 'active')
    .order('is_primary', { ascending: false })
    .order('position', { ascending: true });

  if (!photosData?.length) return { photos: {}, variants: {} };

  const photoIds = photosData.map(p => p.id);

  // Build variant keys with all density variants
  const allVariantKeys = [];
  variantKeys.forEach(key => {
    if (!key.includes('@')) {
      allVariantKeys.push(`${key}@1x`, `${key}@2x`);
    } else {
      allVariantKeys.push(key);
    }
  });

  // Fetch variants
  const { data: variantsData } = await fastify.supabase
    .from('poi_photo_variants')
    .select('photo_id, variant_key, cdn_url, format, width, height')
    .in('photo_id', photoIds)
    .in('variant_key', allVariantKeys);

  // Organize by poi_id
  const photosByPoi = {};
  const variantsByPhoto = {};

  photosData.forEach(photo => {
    if (!photosByPoi[photo.poi_id]) {
      photosByPoi[photo.poi_id] = [];
    }
    photosByPoi[photo.poi_id].push(photo);
  });

  variantsData?.forEach(variant => {
    if (!variantsByPhoto[variant.photo_id]) {
      variantsByPhoto[variant.photo_id] = [];
    }
    variantsByPhoto[variant.photo_id].push(variant);
  });

  return { photos: photosByPoi, variants: variantsByPhoto };
}

// ==== ROUTES ====

export default async function poisRoutes(fastify) {

  // GET /v1/pois - Map + List view (optimized, no cursor pagination)
  fastify.get('/pois', async (request, reply) => {
    try {
      const lang = fastify.getLang(request);

      const {
        bbox,                            // REQUIRED: lat_min,lng_min,lat_max,lng_max
        city = 'paris',
        primary_type,
        subcategory,
        neighbourhood_slug,
        district_slug,
        tags,                            // AND logic
        tags_any,                        // OR logic
        awards,                          // CSV awards providers
        awarded,                         // true/false
        fresh,                           // true/false
        price,                           // legacy: single price 1-4
        price_min,
        price_max,
        rating_min,
        rating_max,
        sort = 'gatto',                  // gatto|price_desc|price_asc|mentions|rating
        limit = 50,
      } = request.query;

      // Validate bbox (required)
      const bboxArray = parseBbox(bbox);
      if (!bboxArray) {
        return reply.code(400).send({
          success: false,
          error: 'bbox is required and must be in format: lat_min,lng_min,lat_max,lng_max',
          timestamp: new Date().toISOString()
        });
      }

      // Parse parameters
      const maxLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 80);

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

      // Call new optimized RPC
      const { data: rows, error } = await fastify.supabase.rpc('list_pois', {
        p_bbox: bboxArray,
        p_city_slug: city,
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
        p_limit: maxLimit
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
      const poiIds = pois.map(p => p.id);

      // Enrich with photos (card variants only)
      const photosData = await enrichWithPhotos(fastify, poiIds, ['card_sq']);

      // Build response items
      const items = pois.map(poi => {
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
              favicon: `https://www.google.com/s2/favicons?domain=${m.domain}&sz=64`,
              url: m.url,
              title: m.title
            }));
          } catch (e) {
            fastify.log.error('Failed to parse mentions_sample:', e);
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
          score: Number(poi.gatto_score || 0),
          scores: {
            gatto: Number(poi.gatto_score || 0),
            digital: Number(poi.digital_score || 0),
            awards_bonus: Number(poi.awards_bonus || 0),
            freshness_bonus: Number(poi.freshness_bonus || 0)
          },
          rating: {
            google: Number(poi.rating_value || 0),
            reviews_count: poi.rating_reviews_count || 0
          },
          mentions_count: poi.mentions_count || 0,
          mentions_sample: mentionsSample,
          tags_flat: poi.tags_flat || []
        };
      });

      // Cache for 10 minutes
      reply.header('Cache-Control', 'public, max-age=600');

      return reply.send({
        success: true,
        data: {
          pois: items,
          total: items.length
        },
        timestamp: new Date().toISOString()
      });

    } catch (err) {
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
      const { slug } = request.params;
      const lang = fastify.getLang(request);

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

      // Parallel fetch: scores, rating, photos, mentions, tags
      const [
        { data: scores },
        { data: rating },
        photosData,
        { data: mentions },
        { data: enrichedTags }
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
          .order('published_at_guess', { ascending: false })
          .limit(6),

        // Tags enrichment
        fastify.supabase.rpc('enrich_tags_with_labels', {
          p_tags: poi.tags,
          p_lang: lang
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
        favicon: `https://www.google.com/s2/favicons?domain=${m.domain}&sz=64`,
        title: m.title,
        excerpt: m.excerpt,
        url: m.url,
        published_at: m.published_at_guess
      }));

      // Build breadcrumb
      const breadcrumb = [
        { label: lang === 'fr' ? 'Accueil' : 'Home', href: '/' },
        { label: lang === 'fr' ? poi.city : poi.city, href: `/${poi.city_slug}` }
      ];

      if (poi.district_slug) {
        breadcrumb.push({
          label: poi.district_slug,
          href: `/${poi.city_slug}/${poi.district_slug}`
        });
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
        scores: {
          gatto: Number(scores?.gatto_score || 0),
          digital: Number(scores?.digital_score || 0),
          awards_bonus: Number(scores?.awards_bonus || 0),
          freshness_bonus: Number(scores?.freshness_bonus || 0),
          calculated_at: scores?.calculated_at
        },
        rating: {
          google: Number(rating?.rating_value || 0),
          reviews_count: rating?.reviews_count || 0
        },
        mentions_count: mentionsSample.length,
        mentions_sample: mentionsSample,
        breadcrumb
      };

      // Cache for 10 minutes
      reply.header('Cache-Control', 'public, max-age=600');

      return reply.send({
        success: true,
        data: response,
        timestamp: new Date().toISOString()
      });

    } catch (err) {
      fastify.log.error('GET /pois/:slug error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Internal server error',
        timestamp: new Date().toISOString()
      });
    }
  });
}
