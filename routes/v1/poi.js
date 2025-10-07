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

// ==== Cursor helpers ====
function encodeCursor(offset) {
  return Buffer.from(String(offset), 'utf8').toString('base64');
}

function decodeCursor(b64) {
  try {
    return parseInt(Buffer.from(String(b64 || ''), 'base64').toString('utf8'), 10) || 0;
  } catch {
    return 0;
  }
}

// ==== Image variant helpers ====
// Returns full photo block with variants or a master fallback
function photoBlockFrom(variantsIndex, photo, wantedKeyPrefix) {
  const photoVariants = variantsIndex[photo.id] || [];
  console.log(`DEBUG photoBlockFrom: photo.id=${photo.id}, wantedKeyPrefix=${wantedKeyPrefix}, available variants:`, 
    photoVariants.map(v => `${v.variant_key}:${v.format}`));
  
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
  
  console.log(`DEBUG photoBlockFrom: filtered variants for ${wantedKeyPrefix}:`, variants.length);
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

// Builds base Supabase query with filters
function buildBaseQuery(fastify, filters, lang) {
  let query = fastify.supabase
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
    .eq('publishable_status', 'eligible');

  // City filter
  if (filters.city && filters.city !== 'paris') {
    query = query.eq('city_slug', filters.city);
  } else {
    query = query.eq('city_slug', 'paris');
  }

  if (filters.category) {
    query = query.eq('category', filters.category);
  }

  if (filters.price) {
    const priceMap = {
      '€': 'PRICE_LEVEL_INEXPENSIVE',
      '€€': 'PRICE_LEVEL_MODERATE',
      '€€€': 'PRICE_LEVEL_EXPENSIVE',
      '€€€€': 'PRICE_LEVEL_VERY_EXPENSIVE'
    };
    if (priceMap[filters.price]) {
      query = query.eq('price_level', priceMap[filters.price]);
    }
  }

  if (filters.neighbourhood_slug) {
    // Convert slug to approximate name for search
    const neighbourhoodName = filters.neighbourhood_slug
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
    query = query.ilike('neighbourhood_name', `%${neighbourhoodName}%`);
  }

  if (filters.district_slug) {
    // Convert slug to approximate name for search
    const districtName = filters.district_slug
      .split('-')
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ');
    query = query.ilike('district_name', `%${districtName}%`);
  }

  if (filters.tags) {
    const tagList = filters.tags.split(',').map(t => t.trim());
    // Search in JSONB tags - PostgREST syntax
    for (const tag of tagList) {
      query = query.contains('tags', `"${tag}"`);
    }
  }

  return query;
}

// Enriches POIs with latest scores
async function enrichWithScores(fastify, poiIds, segment) {
  if (!poiIds.length) return {};

  const { data: scoresData } = await fastify.supabase
    .from('gatto_scores')
    .select('poi_id, gatto_score, digital_score, awards_bonus, freshness_bonus, calculated_at')
    .in('poi_id', poiIds)
    .order('calculated_at', { ascending: false });

  // Deduplicate to keep latest score per poi
  const latestScores = {};
  scoresData?.forEach(score => {
    if (!latestScores[score.poi_id]) {
      latestScores[score.poi_id] = score;
    }
  });

  return latestScores;
}

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

// Enriches POIs with latest Google ratings
async function enrichWithRatings(fastify, poiIds) {
  if (!poiIds.length) return {};

  const { data: ratingsData } = await fastify.supabase
    .from('rating_snapshot')
    .select('poi_id, rating_value, reviews_count')
    .in('poi_id', poiIds)
    .eq('source_id', 'google')
    .order('captured_at', { ascending: false });

  // Deduplicate to keep latest rating per poi
  const latestRatings = {};
  ratingsData?.forEach(rating => {
    if (!latestRatings[rating.poi_id]) {
      latestRatings[rating.poi_id] = rating;
    }
  });

  return latestRatings;
}

// Enriches POIs with mentions data
async function enrichWithMentions(fastify, poiIds, includeDetails = false) {
  if (!poiIds.length) return {};

  // Count distinct domains per poi
  const { data: mentionsCount } = await fastify.supabase
    .from('ai_mention')
    .select('poi_id, domain')
    .in('poi_id', poiIds)
    .eq('ai_decision', 'ACCEPT');

  const countsByPoi = {};
  const domainsByPoi = {};

  mentionsCount?.forEach(mention => {
    if (!countsByPoi[mention.poi_id]) {
      countsByPoi[mention.poi_id] = new Set();
      domainsByPoi[mention.poi_id] = new Set();
    }
    countsByPoi[mention.poi_id].add(mention.domain);
    domainsByPoi[mention.poi_id].add(mention.domain);
  });

  // Convert Sets to counts and sample domains
  const result = {};
  Object.keys(countsByPoi).forEach(poiId => {
    const domains = Array.from(domainsByPoi[poiId]);
    result[poiId] = {
      sources_count: countsByPoi[poiId].size,
      sources_sample: domains.map(domain => ({
        domain,
        favicon: `https://www.google.com/s2/favicons?domain=${domain}&sz=64`
      }))
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
  
  // City
  breadcrumb.push({
    label: poi.city || 'Paris',
    href: `/${poi.city_slug || 'paris'}`
  });

  // Category
  if (poi.category) {
    const categoryLabel = lang === 'en' ? poi.category + 's' : pluralizeCategoryFr(poi.category);
    breadcrumb.push({
      label: categoryLabel.charAt(0).toUpperCase() + categoryLabel.slice(1),
      href: `/${poi.city_slug || 'paris'}/${poi.category}s`
    });
  }

  // District
  if (poi.district_name) {
    const districtSlug = buildDistrictSlug(poi.district_name);
    breadcrumb.push({
      label: poi.district_name,
      href: `/${poi.city_slug || 'paris'}/${poi.category}s/${districtSlug}`
    });
  }

  return breadcrumb;
}

// Sorts items by segment or default (Gatto score)
function sortItemsBySegment(items, segment) {
  if (segment === 'digital') {
    return items.sort((a, b) => (b.scores?.digital ?? -1) - (a.scores?.digital ?? -1));
  }
  if (segment === 'awarded') {
    return items.sort((a, b) => {
      const byAwards = (b.scores?.awards_bonus ?? -1) - (a.scores?.awards_bonus ?? -1);
      if (byAwards !== 0) return byAwards;
      return (b.scores?.gatto ?? -1) - (a.scores?.gatto ?? -1);
    });
  }
  if (segment === 'fresh') {
    return items.sort((a, b) => {
      const byFresh = (b.scores?.freshness_bonus ?? -1) - (a.scores?.freshness_bonus ?? -1);
      if (byFresh !== 0) return byFresh;
      return (b.scores?.gatto ?? -1) - (a.scores?.gatto ?? -1);
    });
  }
  // Default: best Gatto score first
  return items.sort((a, b) => (b.scores?.gatto ?? -1) - (a.scores?.gatto ?? -1));
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
  
  // GET /v1/poi - Paginated list
  fastify.get('/poi', async (request, reply) => {
    try {
      const lang = fastify.getLang(request);
      const {
        view = 'card',
        segment,
        category,
        neighbourhood_slug,
        district_slug,
        tags,
        price,
        city = 'paris',
        limit = 24,
        cursor,
        fields
      } = request.query;

      // Validation
      const maxLimit = Math.min(Math.max(parseInt(limit, 10), 1), 50);
      const offset = decodeCursor(cursor);

      const filters = {
        city,
        category,
        neighbourhood_slug,
        district_slug,
        tags,
        price
      };

      // Build base query - fetch more than needed for proper sorting
      let query = buildBaseQuery(fastify, filters, lang);
      
      // For segments, we need to fetch more data to sort properly
      const fetchLimit = segment ? Math.min(maxLimit * 3, 150) : maxLimit;
      query = query.range(0, fetchLimit - 1);

      // Execute main query
      const { data: pois, error } = await query;
      
      if (error) {
        fastify.log.error('Error fetching POIs:', error);
        return reply.error('Failed to fetch POIs', 500);
      }

      if (!pois?.length) {
        return reply.success({
          items: [],
          next_cursor: null,
          previous_cursor: null
        });
      }

      const poiIds = pois.map(p => p.id);

      // Parallel enrichment - use exact variant keys
      const variantKeys = view === 'card' ? 
        ['card_sq@1x', 'card_sq@2x'] : 
        ['card_sq@1x', 'card_sq@2x', 'detail@1x', 'detail@2x', 'thumb_small@1x', 'thumb_small@2x'];
      
      const [scores, photosData, ratings, mentions] = await Promise.all([
        enrichWithScores(fastify, poiIds, segment),
        enrichWithPhotos(fastify, poiIds, variantKeys),
        enrichWithRatings(fastify, poiIds),
        enrichWithMentions(fastify, poiIds, false)
      ]);

      // Build items with enriched data
      const enrichedItems = pois.map(poi => {
        const score = scores[poi.id];
        const poiPhotos = photosData.photos[poi.id] || [];
        const primaryPhoto = poiPhotos.find(p => p.is_primary) || poiPhotos[0];
        const rating = ratings[poi.id];
        const mentionData = mentions[poi.id];

        // Photo with all variants
        let photo = null;
        if (primaryPhoto) {
          const photoBlock = photoBlockFrom(photosData.variants, primaryPhoto, 'card_sq');
          if (photoBlock) {
            photo = {
              variants: photoBlock.variants,
              width: (photoBlock.variants[0] && photoBlock.variants[0].width) || null,
              height: (photoBlock.variants[0] && photoBlock.variants[0].height) || null,
              dominant_color: photoBlock.dominant_color,
              blurhash: photoBlock.blurhash
            };
          }
        }

        // Base item data
        const item = {
          id: poi.id,
          slug: pickLang(poi, lang, 'slug'),
          name: pickLang(poi, lang, 'name'),
          category: poi.category,
          district: poi.district_name,
          neighbourhood: poi.neighbourhood_name
        };

        // Photo
        if (photo) {
          item.photo = photo;
        }

        // Scores
        if (score) {
          item.score = score.gatto_score;
          
          // Detailed scores if requested
          if (!fields || fields.includes('scores')) {
            item.scores = {
              gatto: score.gatto_score,
              digital: score.digital_score,
              awards_bonus: score.awards_bonus,
              freshness_bonus: score.freshness_bonus
            };
          }
        }

        // Google rating
        if (rating) {
          item.rating = {
            google: rating.rating_value,
            reviews_count: rating.reviews_count
          };
        }

        // Mentions
        if (mentionData) {
          item.sources_count = mentionData.sources_count;
          item.sources_sample = mentionData.sources_sample;
        }

        // Additional fields for detail view
        if (view === 'detail') {
          item.summary = pickLang(poi, lang, 'ai_summary');
          item.coords = { lat: poi.lat, lng: poi.lng };
          item.price_level = poi.price_level;
          item.opening_hours = poi.opening_hours;
          
          // Gallery for detail view
          if (poiPhotos.length > 1) {
            const galleryPhotos = poiPhotos
              .filter(p => !p.is_primary)
              .slice(0, 5)
              .map(p => {
                const galleryBlock = photoBlockFrom(photosData.variants, p, 'thumb_small');
                return galleryBlock ? {
                  variants: galleryBlock.variants,
                  width: (galleryBlock.variants[0] && galleryBlock.variants[0].width) || null,
                  height: (galleryBlock.variants[0] && galleryBlock.variants[0].height) || null,
                  dominant_color: galleryBlock.dominant_color,
                  blurhash: galleryBlock.blurhash
                } : null;
              })
              .filter(Boolean);
            
            if (galleryPhotos.length) {
              item.photos = {
                primary: photo,
                gallery: galleryPhotos
              };
              delete item.photo;
            }
          }
        }

        // Filter fields if requested
        return filterFields(item, fields);
      });

      // Sort by segment
      const sortedItems = sortItemsBySegment(enrichedItems, segment);

      // Apply pagination
      const pageItems = sortedItems.slice(offset, offset + maxLimit);
      
      // Calculate cursors
      const hasMore = (offset + maxLimit) < sortedItems.length;
      const nextCursor = hasMore ? encodeCursor(offset + maxLimit) : null;
      const previousCursor = offset > 0 ? encodeCursor(Math.max(offset - maxLimit, 0)) : null;

      reply.header('Cache-Control', 'public, max-age=300');
      return reply.success({
        items: pageItems,
        next_cursor: nextCursor,
        previous_cursor: previousCursor
      });

    } catch (error) {
      fastify.log.error('Error in GET /poi:', error.message, error.stack);
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
      const [scores, photosData, ratings, mentions] = await Promise.all([
        enrichWithScores(fastify, [poiId]),
        enrichWithPhotos(fastify, [poiId], ['detail@1x', 'detail@2x', 'thumb_small@1x', 'thumb_small@2x']),
        enrichWithRatings(fastify, [poiId]),
        enrichWithMentions(fastify, [poiId], true)
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
        summary: pickLang(poi, lang, 'ai_summary'),
        opening_hours: poi.opening_hours
      };

      // Photos
      const primaryBlock = primaryPhoto ? photoBlockFrom(photosData.variants, primaryPhoto, 'detail') : null;

      const galleryBlocks = otherPhotos.map(ph => {
        const pb = photoBlockFrom(photosData.variants, ph, 'thumb_small');
        return pb && {
          variants: pb.variants,
          width: (pb.variants[0] && pb.variants[0].width) || null,
          height: (pb.variants[0] && pb.variants[0].height) || null,
          dominant_color: pb.dominant_color || null,
          blurhash: pb.blurhash || null
        };
      }).filter(Boolean);

      result.photos = {
        primary: primaryBlock ? {
          variants: primaryBlock.variants,
          width: (primaryBlock.variants[0] && primaryBlock.variants[0].width) || null,
          height: (primaryBlock.variants[0] && primaryBlock.variants[0].height) || null,
          dominant_color: primaryBlock.dominant_color || null,
          blurhash: primaryBlock.blurhash || null
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
      if (mentionData?.mentions) {
        result.mentions = mentionData.mentions;
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