// ==== HELPERS ====

// Multi-language field picker with fallback
function pickLang(obj, lang, base) {
  const primary = obj[`${base}_${lang}`];
  const fallback = lang === 'fr' ? obj[`${base}_en`] : obj[`${base}_fr`];
  const legacy = obj[base];
  
  return primary || fallback || legacy || null;
}

// Converts string to URL-friendly slug
function slugify(str) {
  if (!str) return '';
  return str
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .trim('-');
}

// Simple category pluralization for French
function pluralizeCategoryFr(category) {
  if (!category) return category;
  
  const exceptions = {
    'bar': 'bars',
    'café': 'cafés',
    'restaurant': 'restaurants',
    'boulangerie': 'boulangeries',
    'patisserie': 'patisseries',
    'hotel': 'hotels'
  };
  
  return exceptions[category.toLowerCase()] || category + 's';
}

// ==== Keyset pagination helpers (score + id) ====
function encodeKeysetCursor(obj) {
  return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64');
}

function decodeKeysetCursor(b64) {
  try { 
    return JSON.parse(Buffer.from(String(b64 || ''), 'base64').toString('utf8')); 
  } catch { 
    return null; 
  }
}

// Prix -> enum text pour l'arg p_price_level
const PRICE_MAP = {
  '€': 'PRICE_LEVEL_INEXPENSIVE',
  '€€': 'PRICE_LEVEL_MODERATE',
  '€€€': 'PRICE_LEVEL_EXPENSIVE',
  '€€€€': 'PRICE_LEVEL_VERY_EXPENSIVE'
};

// Title-case simple pour transformer des slugs en labels
const capFromSlug = (s) => s
  ? s.split('-').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
  : null;

// ==== Image variant helpers ====
// Returns full photo block with variants or a master fallback
function photoBlockFrom(variantsIndex, photo, wantedKeyPrefix) {
  const photoVariants = variantsIndex[photo.id] || [];
  
  const variants = photoVariants
    .filter(v => v.variant_key.startsWith(wantedKeyPrefix))
    .sort((a, b) => {
      // Sort by variant_key first (1x before 2x), then by format preference
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

function buildDistrictSlug(districtName) {
  if (!districtName) return '';
  return slugify(districtName);
}

function buildNeighbourhoodSlug(neighbourhoodName) {
  if (!neighbourhoodName) return '';
  return slugify(neighbourhoodName);
}

// ==== BUSINESS LOGIC ====

// Enriches POIs with photos and variants
async function enrichWithPhotos(fastify, poiIds, variantKeys = ['card_sq']) {
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
  
  // Fetch variants for requested keys only
  const { data: variantsData } = await fastify.supabase
    .from('poi_photo_variants')
    .select('photo_id, variant_key, cdn_url, format, width, height')
    .in('photo_id', photoIds)
    .in('variant_key', variantKeys);

  // Organize by poi_id
  const photosByPoi = {};
  const variantsByPhoto = {};

  photosData.forEach(photo => {
    if (!photosByPoi[photo.poi_id]) {
      photosByPoi[photo.poi_id] = [];
    }
    photosByPoi[photo.poi_id].push(photo);
  });

  // Organize variants by photo_id
  variantsData?.forEach(variant => {
    if (!variantsByPhoto[variant.photo_id]) {
      variantsByPhoto[variant.photo_id] = [];
    }
    variantsByPhoto[variant.photo_id].push(variant);
  });

  return { photos: photosByPoi, variants: variantsByPhoto };
}


// Enriches POIs with mentions data
async function enrichWithMentions(fastify, poiIds, includeDetails = false) {
  if (!poiIds.length) return {};

  // Count distinct domains per poi
  const { data: mentionsCount } = await fastify.supabase
    .from('ai_mention')
    .select('poi_id, domain, url, title')
    .in('poi_id', poiIds)
    .eq('ai_decision', 'ACCEPT');

  const countsByPoi = {};
  const domainsByPoi = {};
  const mentionsByDomain = {};

  mentionsCount?.forEach(mention => {
    if (!countsByPoi[mention.poi_id]) {
      countsByPoi[mention.poi_id] = new Set();
      domainsByPoi[mention.poi_id] = new Set();
      mentionsByDomain[mention.poi_id] = new Map();
    }
    countsByPoi[mention.poi_id].add(mention.domain);
    domainsByPoi[mention.poi_id].add(mention.domain);
    
    // Store one mention per domain for url and title
    if (!mentionsByDomain[mention.poi_id].has(mention.domain)) {
      mentionsByDomain[mention.poi_id].set(mention.domain, {
        url: mention.url,
        title: mention.title
      });
    }
  });

  // Convert Sets to counts and sample domains
  const result = {};
  Object.keys(countsByPoi).forEach(poiId => {
    const domains = Array.from(domainsByPoi[poiId]);
    result[poiId] = {
      mentions_count: countsByPoi[poiId].size,
      mentions_sample: domains.map(domain => {
        const mentionData = mentionsByDomain[poiId].get(domain);
        return {
          domain,
          favicon: `https://www.google.com/s2/favicons?domain=${domain}&sz=64`,
          url: mentionData?.url || null,
          title: mentionData?.title || null
        };
      })
    };
  });

  // Include mention details for detail view
  if (includeDetails && poiIds.length === 1) {
    const poiId = poiIds[0];
    const { data: mentionsDetails } = await fastify.supabase
      .from('ai_mention')
      .select('domain, title, excerpt, url, published_at_guess, last_seen_at')
      .eq('poi_id', poiId)
      .eq('ai_decision', 'ACCEPT')
      .order('published_at_guess', { ascending: false, nullsFirst: false })
      .order('last_seen_at', { ascending: false })
      .limit(6);

    if (mentionsDetails?.length) {
      result[poiId].mentions = mentionsDetails.map(mention => ({
        domain: mention.domain,
        favicon: `https://www.google.com/s2/favicons?domain=${mention.domain}&sz=64`,
        title: mention.title,
        excerpt: mention.excerpt,
        url: mention.url
      }));
    }
  }

  return result;
}

// Builds breadcrumb navigation for POI detail
function buildBreadcrumb(poi, lang) {
  const breadcrumb = [];
  
  // Accueil
  breadcrumb.push({
    label: lang === 'en' ? 'Home' : 'Accueil',
    href: '/'
  });

  // City
  breadcrumb.push({
    label: poi.city || 'Paris',
    href: `/${poi.city_slug || 'paris'}`
  });

  // District
  if (poi.district_name) {
    const districtSlug = buildDistrictSlug(poi.district_name);
    breadcrumb.push({
      label: poi.district_name,
      href: `/${poi.city_slug || 'paris'}/${districtSlug}`
    });
  }

  // Neighbourhood
  if (poi.neighbourhood_name) {
    const neighbourhoodSlug = buildNeighbourhoodSlug(poi.neighbourhood_name);
    breadcrumb.push({
      label: poi.neighbourhood_name,
      href: `/${poi.city_slug || 'paris'}/${poi.district_name ? buildDistrictSlug(poi.district_name) + '/' : ''}${neighbourhoodSlug}`
    });
  }

  return breadcrumb;
}


// Filters object fields based on requested fields
function filterFields(data, fields) {
  if (!fields) return data;
  
  const fieldSet = new Set(fields.split(',').map(f => f.trim()));
  const filtered = {};
  
  // Always include these fields
  const alwaysInclude = ['id', 'slug', 'name'];
  alwaysInclude.forEach(field => {
    if (data[field] !== undefined) {
      filtered[field] = data[field];
    }
  });
  
  // Optional fields
  fieldSet.forEach(field => {
    if (data[field] !== undefined) {
      filtered[field] = data[field];
    }
  });
  
  return filtered;
}

// ==== ROUTES ====

export default async function poiRoutes(fastify, opts) {
  
  // GET /v1/poi - Paginated list with RPC
  fastify.get('/poi', async (request, reply) => {
    try {
      const lang = fastify.getLang(request);

      const {
        view = 'card',
        segment,                         // 'gatto' | 'digital' | 'awarded' | 'fresh' (optionnel)
        category,                        // string (enum côté DB)
        neighbourhood_slug,              // ex: 'haut-marais'
        district_slug,                   // ex: '10e-arrondissement'
        tags,                            // ex: 'trendy,modern' (AND logique)
        tags_any,                        // ex: 'terrace,michelin' (OR logique)
        price,                           // '€'| '€€' | ...
        city = 'paris',
        limit = 24,
        cursor,                          // keyset base64 {score,id}
        fields                           // ex: 'scores,rating,tags'
      } = request.query;

      // bornes défensives
      const maxLimit = Math.min(Math.max(parseInt(limit, 10) || 24, 1), 50);

      // normalisations
      const neighbourhoodName = capFromSlug(neighbourhood_slug);
      const districtName = capFromSlug(district_slug);
      const priceLevel = price ? (PRICE_MAP[price] || null) : null;

      // Parsing des tags pour filtrage AND/OR
      const tagsAll = tags
        ? tags.split(',').map(t => t.trim().toLowerCase()).filter(Boolean)
        : null;

      const tagsAny = tags_any
        ? tags_any.split(',').map(t => t.trim().toLowerCase()).filter(Boolean)
        : null;

      // on unifie: branche unique par RPC (même sans segment -> défaut géré côté SQL)
      const after = decodeKeysetCursor(cursor);
      const segCol =
        segment === 'digital' ? 'digital_score' :
        segment === 'awarded' ? 'awards_bonus' :
        segment === 'fresh'   ? 'freshness_bonus' :
                                'gatto_score';

      const rpcParams = {
        p_city_slug: city || 'paris',
        p_category: category || null,
        p_price_level: priceLevel,
        p_neighbourhood: neighbourhoodName,
        p_district: districtName,
        p_tags_all: tagsAll,               // filtrage AND logique
        p_segment: segment || 'gatto',     // défaut unifié
        p_limit: maxLimit,
        p_after_score: after?.score ?? null,
        p_after_id: after?.id ?? null,
        p_tags_any: tagsAny                // filtrage OR logique
      };

      const { data: rows, error } = await fastify.supabase.rpc('list_pois_segment', rpcParams);
      if (error) {
        fastify.log.error('RPC list_pois_segment error:', error);
        return reply.error('Failed to fetch POIs', 500);
      }

      // rows = POI + derniers scores déjà joints
      // Prépare un map pour les scores, et une liste POI nettoyée (sans colonnes de score)
      const poiScores = {};
      const pois = rows.map(r => {
        poiScores[r.id] = {
          poi_id: r.id,
          gatto_score: Number(r.gatto_score ?? 0),
          digital_score: Number(r.digital_score ?? 0),
          awards_bonus: Number(r.awards_bonus ?? 0),
          freshness_bonus: Number(r.freshness_bonus ?? 0),
          calculated_at: r.calculated_at
        };

        // NE PAS jeter tags_flat ici
        const {
          gatto_score, digital_score, awards_bonus, freshness_bonus, calculated_at,
          ...poiData
        } = r;

        return poiData; // poiData contient encore tags_flat
      });

      // next_cursor (keyset) si page pleine
      let nextCursor = null;
      if (pois.length === maxLimit) {
        const last = rows[rows.length - 1];
        nextCursor = encodeKeysetCursor({ score: Number(last[segCol] ?? 0), id: last.id });
      }

      // Enrichissements: photos, ratings (vue), mentions
      const poiIds = pois.map(p => p.id);
      const variantKeys = view === 'card'
        ? ['card_sq@1x', 'card_sq@2x']
        : ['card_sq@1x', 'card_sq@2x', 'detail@1x', 'detail@2x', 'thumb_small@1x', 'thumb_small@2x'];

      const [photosData, ratings, mentions] = await Promise.all([
        enrichWithPhotos(fastify, poiIds, variantKeys),

        // ratings depuis la vue 'public.latest_google_rating'
        (async () => {
          if (!poiIds.length) return {};
          const { data, error } = await fastify.supabase
            .from('latest_google_rating')
            .select('poi_id, rating_value, reviews_count')
            .in('poi_id', poiIds);

          if (error) {
            fastify.log.warn('latest_google_rating fetch error:', error);
            return {};
          }
          const m = {};
          (data || []).forEach(r => { m[r.poi_id] = r; });
          return m;
        })(),

        enrichWithMentions(fastify, poiIds, false)
      ]);

      // Construction des items (card|detail, champs optionnels)
      const enrichedItems = pois.map(poi => {
        const score = poiScores[poi.id];

        // Photo principale (ou fallback 1ère)
        const poiPhotos = photosData.photos[poi.id] || [];
        const primaryPhoto = poiPhotos.find(p => p.is_primary) || poiPhotos[0];

        let photo = null;
        if (primaryPhoto) {
          const block = photoBlockFrom(photosData.variants, primaryPhoto, 'card_sq');
          if (block) {
            photo = {
              variants: block.variants,
              width: block.variants[0]?.width ?? null,
              height: block.variants[0]?.height ?? null,
              dominant_color: block.dominant_color,
              blurhash: block.blurhash
            };
          }
        }

        const item = {
          id: poi.id,
          slug: pickLang(poi, lang, 'slug'),
          name: pickLang(poi, lang, 'name'),
          category: poi.category,
          district: poi.district_name,
          neighbourhood: poi.neighbourhood_name
        };

        if (photo) item.photo = photo;

        if (score) {
          item.score = score.gatto_score;
          if (!fields || fields.includes('scores')) {
            item.scores = {
              gatto: score.gatto_score,
              digital: score.digital_score,
              awards_bonus: score.awards_bonus,
              freshness_bonus: score.freshness_bonus
            };
          }
        }

        const rating = ratings[poi.id];
        if (rating) {
          item.rating = {
            google: rating.rating_value,
            reviews_count: rating.reviews_count
          };
        }

        const mentionData = mentions[poi.id];
        if (mentionData) {
          item.mentions_count = mentionData.mentions_count;
          item.mentions_sample = mentionData.mentions_sample;
        }

        // Inclure tags_flat si demandé dans fields
        if (!fields || fields.includes('tags') || fields.includes('tags_flat')) {
          item.tags_flat = poi.tags_flat || null;
        }

        if (view === 'detail') {
          item.summary = pickLang(poi, lang, 'ai_summary');
          item.coords = { lat: Number(poi.lat), lng: Number(poi.lng) };
          item.price_level = poi.price_level;
          item.opening_hours = poi.opening_hours;

          // petite galerie (5 max)
          const galleryPhotos = (photosData.photos[poi.id] || [])
            .filter(p => !p.is_primary)
            .slice(0, 5)
            .map(p => {
              const block = photoBlockFrom(photosData.variants, p, 'thumb_small');
              return block ? {
                variants: block.variants,
                width: block.variants[0]?.width ?? null,
                height: block.variants[0]?.height ?? null,
                dominant_color: block.dominant_color,
                blurhash: block.blurhash
              } : null;
            })
            .filter(Boolean);

          if (galleryPhotos.length) {
            item.photos = { primary: photo, gallery: galleryPhotos };
            delete item.photo;
          }
        }

        return filterFields(item, fields);
      });

      reply.header('Cache-Control', 'public, max-age=300');
      return reply.success({
        items: enrichedItems,
        next_cursor: nextCursor,
        previous_cursor: null // keyset: pas de prev
      });

    } catch (error) {
      fastify.log.error('Error in GET /poi:', error);
      return reply.error('Internal server error', 500);
    }
  });

  // GET /v1/poi/:slug - POI detail
  fastify.get('/poi/:slug', async (request, reply) => {
    try {
      const { slug } = request.params;
      const lang = fastify.getLang(request);

      // Find POI by slug (multi-lang)
      const { data: pois, error } = await fastify.supabase
        .from('poi')
        .select(`
          id,
          google_place_id,
          city_slug,
          name,
          name_en,
          name_fr,
          slug_en,
          slug_fr,
          category,
          address_street,
          city,
          country,
          lat,
          lng,
          opening_hours,
          price_level,
          phone,
          website,
          district_name,
          neighbourhood_name,
          publishable_status,
          ai_summary,
          ai_summary_en,
          ai_summary_fr,
          tags,
          created_at,
          updated_at
        `)
        .eq('publishable_status', 'eligible')
        .or(`slug_${lang}.eq.${slug},slug_en.eq.${slug},slug_fr.eq.${slug}`)
        .limit(1);

      if (error) {
        fastify.log.error('Error fetching POI detail:', error);
        return reply.error('Failed to fetch POI', 500);
      }

      if (!pois?.length) {
        return reply.error('POI not found', 404);
      }

      const poi = pois[0];
      const poiId = poi.id;

      // Parallel enrichment
      const [scores, photosData, ratings, mentions, enrichedTags] = await Promise.all([
        // Fetch scores from latest_poi_scores
        (async () => {
          const { data, error } = await fastify.supabase
            .from('latest_poi_scores')
            .select('poi_id, gatto_score, digital_score, awards_bonus, freshness_bonus, calculated_at')
            .eq('poi_id', poiId)
            .limit(1);
          
          if (error) {
            fastify.log.warn('latest_poi_scores fetch error:', error);
            return {};
          }
          const result = {};
          if (data?.[0]) {
            result[poiId] = data[0];
          }
          return result;
        })(),
        
        enrichWithPhotos(fastify, [poiId], ['detail@1x', 'detail@2x', 'thumb_small@1x', 'thumb_small@2x', 'gallery@1x']),
        
        // Fetch ratings from latest_google_rating
        (async () => {
          const { data, error } = await fastify.supabase
            .from('latest_google_rating')
            .select('poi_id, rating_value, reviews_count')
            .eq('poi_id', poiId)
            .limit(1);
          
          if (error) {
            fastify.log.warn('latest_google_rating fetch error:', error);
            return {};
          }
          const result = {};
          if (data?.[0]) {
            result[poiId] = data[0];
          }
          return result;
        })(),
        
        enrichWithMentions(fastify, [poiId], true),
        
        // Enrich tags with taxonomy labels
        (async () => {
          if (!poi.tags) return {};
          
          const { data, error } = await fastify.supabase.rpc('enrich_tags_with_labels', {
            p_tags: poi.tags,
            p_lang: lang
          });
          
          if (error) {
            fastify.log.warn('Failed to enrich tags with labels:', error);
            return poi.tags; // Fallback to original tags
          }
          
          return data || {};
        })()
      ]);

      const score = scores[poiId];
      const poiPhotos = photosData.photos[poiId] || [];
      const primaryPhoto = poiPhotos.find(p => p.is_primary) || poiPhotos[0];
      const otherPhotos = poiPhotos.filter(p => !p.is_primary);
      const rating = ratings[poiId];
      const mentionData = mentions[poiId];

      // Build detailed response
      const result = {
        id: poi.id,
        slug: pickLang(poi, lang, 'slug'),
        name: pickLang(poi, lang, 'name'),
        category: poi.category,
        city: poi.city,
        district: poi.district_name,
        neighbourhood: poi.neighbourhood_name,
        coords: { lat: poi.lat, lng: poi.lng },
        price_level: poi.price_level,
        tags_keys: poi.tags || {},
        tags: enrichedTags,
        summary: pickLang(poi, lang, 'ai_summary'),
        opening_hours: poi.opening_hours,
        google_place_id: poi.google_place_id,
        address: poi.address_street && poi.city ? `${poi.address_street}, ${poi.city}` : poi.address_street || poi.city || null,
        website: poi.website,
        phone: poi.phone
      };

      // Photos
      const primaryBlock = primaryPhoto ? photoBlockFrom(photosData.variants, primaryPhoto, 'detail') : null;
      const primaryGalleryBlock = primaryPhoto ? photoBlockFrom(photosData.variants, primaryPhoto, 'gallery') : null;

      const galleryBlocks = otherPhotos.map(ph => {
        const thumbBlock = photoBlockFrom(photosData.variants, ph, 'thumb_small');
        const galleryBlock = photoBlockFrom(photosData.variants, ph, 'gallery');
        
        if (!thumbBlock) return null;
        
        return {
          variants: thumbBlock.variants,
          width: (thumbBlock.variants[0] && thumbBlock.variants[0].width) || null,
          height: (thumbBlock.variants[0] && thumbBlock.variants[0].height) || null,
          dominant_color: thumbBlock.dominant_color || null,
          blurhash: thumbBlock.blurhash || null,
          gallery: galleryBlock ? {
            variants: galleryBlock.variants,
            width: (galleryBlock.variants[0] && galleryBlock.variants[0].width) || null,
            height: (galleryBlock.variants[0] && galleryBlock.variants[0].height) || null,
            dominant_color: galleryBlock.dominant_color || null,
            blurhash: galleryBlock.blurhash || null
          } : null
        };
      }).filter(Boolean);

      result.photos = {
        primary: primaryBlock ? {
          variants: primaryBlock.variants,
          width: (primaryBlock.variants[0] && primaryBlock.variants[0].width) || null,
          height: (primaryBlock.variants[0] && primaryBlock.variants[0].height) || null,
          dominant_color: primaryBlock.dominant_color || null,
          blurhash: primaryBlock.blurhash || null,
          gallery: primaryGalleryBlock ? {
            variants: primaryGalleryBlock.variants,
            width: (primaryGalleryBlock.variants[0] && primaryGalleryBlock.variants[0].width) || null,
            height: (primaryGalleryBlock.variants[0] && primaryGalleryBlock.variants[0].height) || null,
            dominant_color: primaryGalleryBlock.dominant_color || null,
            blurhash: primaryGalleryBlock.blurhash || null
          } : null
        } : null,
        gallery: galleryBlocks
      };

      // Scores
      if (score) {
        result.scores = {
          gatto: score.gatto_score,
          digital: score.digital_score,
          awards_bonus: score.awards_bonus,
          freshness_bonus: score.freshness_bonus,
          calculated_at: score.calculated_at
        };
      }

      // Rating
      if (rating) {
        result.rating = {
          google: rating.rating_value,
          reviews_count: rating.reviews_count
        };
      }

      // Mentions
      if (mentionData) {
        if (mentionData.mentions_count) {
          result.mentions_count = mentionData.mentions_count;
        }
        if (mentionData.mentions_sample) {
          result.mentions_sample = mentionData.mentions_sample;
        }
      }

      // Breadcrumb
      result.breadcrumb = buildBreadcrumb(poi, lang);

      reply.header('Cache-Control', 'public, max-age=300');
      return reply.success(result);

    } catch (error) {
      fastify.log.error('Error in GET /poi/:slug:', error.message, error.stack);
      return reply.error('Internal server error', 500);
    }
  });
}