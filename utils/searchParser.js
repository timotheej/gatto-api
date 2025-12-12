/**
 * Main search query parser
 * Detects intent and converts natural language queries to structured parameters
 * @module utils/searchParser
 */

import { LRUCache } from 'lru-cache';
import {
  normalizeQuery,
  validateQuery,
  getAdaptiveSimilarityThreshold
} from './searchNormalizer.js';
import { matchTypes } from './searchSynonyms.js';

/**
 * Parse cache (reduce DB lookups for repeated queries)
 * TTL: 1 hour, Max: 5000 entries
 */
const parseCache = new LRUCache({
  max: 5000,
  ttl: 1000 * 60 * 60  // 1 hour
});

/**
 * Detects the search mode based on query patterns
 * Returns: 'address' | 'natural' | 'name_or_type'
 *
 * @param {string} query - Normalized query
 * @returns {string} - Detected mode
 */
function detectSearchMode(query) {
  const normalized = query.toLowerCase();

  // V2: Address detection (disabled for V1)
  // Patterns: "12 rue de Rivoli", "25 avenue des Champs-Élysées"
  if (false && /\d+\s+(rue|avenue|boulevard|bd|av|place)/i.test(normalized)) {
    return 'address';
  }

  // V2: Natural language processing (disabled for V1)
  // Patterns: "meilleur italien du 11e", "où manger des sushi"
  if (false && /\b(meilleur|top|où|je veux|cherche|envie|trouver)\b/i.test(normalized)) {
    return 'natural';
  }

  // V1: Default to name or type matching
  return 'name_or_type';
}

/**
 * Parses name_or_type mode queries
 * Tests if query matches a type synonym, otherwise treats as name search
 *
 * @param {string} originalQuery - Original user query (preserve case)
 * @param {string} normalized - Normalized query
 * @param {string} lang - Language (fr|en)
 * @param {object} supabase - Supabase client
 * @returns {Promise<object>} - Parsed parameters
 */
async function parseNameOrType(originalQuery, normalized, lang, supabase) {
  // 1. Test if query matches a type synonym
  const typeKeys = await matchTypes(normalized, lang, supabase);

  if (typeKeys.length > 0) {
    // It's a type query!
    return {
      mode: 'type',
      type_keys: typeKeys,
      display: originalQuery,
      original_query: originalQuery
    };
  }

  // 2. Otherwise, treat as name search with fuzzy matching
  const threshold = getAdaptiveSimilarityThreshold(normalized);

  return {
    mode: 'name',
    name_search: originalQuery,  // Keep original case for display
    name_similarity_threshold: threshold,
    display: `POIs nommés "${originalQuery}"`,
    original_query: originalQuery
  };
}

/**
 * Main search query parser
 * Converts user query into structured parameters for list_pois()
 *
 * @param {string} query - Raw user query
 * @param {string} city - City context (default: 'paris')
 * @param {string} lang - Language (default: 'fr')
 * @param {object} supabase - Supabase client
 * @returns {Promise<object>} - Parsed search parameters
 * @throws {Error} - If query is invalid
 *
 * @example
 * // Type query
 * await parseSearchQuery('italien', 'paris', 'fr', supabase)
 * // Returns: {
 * //   mode: 'type',
 * //   type_keys: ['italian_restaurant'],
 * //   display: 'italien',
 * //   original_query: 'italien'
 * // }
 *
 * @example
 * // Name query
 * await parseSearchQuery('Le Comptoir', 'paris', 'fr', supabase)
 * // Returns: {
 * //   mode: 'name',
 * //   name_search: 'Le Comptoir',
 * //   name_similarity_threshold: 0.4,
 * //   display: 'POIs nommés "Le Comptoir"',
 * //   original_query: 'Le Comptoir'
 * // }
 */
export async function parseSearchQuery(query, city = 'paris', lang = 'fr', supabase) {
  // 1. Validate query
  const validation = validateQuery(query);
  if (!validation.valid) {
    throw new Error(validation.error);
  }

  // 2. Normalize for consistent matching
  const normalized = normalizeQuery(query);

  // 3. Detect search mode
  const mode = detectSearchMode(normalized);

  // 4. Parse based on mode
  switch (mode) {
    case 'address':
      // V2: To be implemented
      throw new Error('Address search not yet supported');

    case 'natural':
      // V2: To be implemented (LLM or pattern-based NLP)
      throw new Error('Natural language search not yet supported');

    case 'name_or_type':
    default:
      return await parseNameOrType(query, normalized, lang, supabase);
  }
}

/**
 * Cached version of parseSearchQuery
 * Reduces DB lookups for repeated queries (e.g., "italien" searched 100x)
 *
 * @param {string} query - Raw user query
 * @param {string} city - City context
 * @param {string} lang - Language
 * @param {object} supabase - Supabase client
 * @returns {Promise<object>} - Parsed search parameters (with from_cache flag)
 *
 * @example
 * // First call: hits DB
 * const result1 = await parseSearchQueryCached('italien', 'paris', 'fr', supabase)
 * // result1.from_cache === false
 *
 * // Second call: from cache
 * const result2 = await parseSearchQueryCached('italien', 'paris', 'fr', supabase)
 * // result2.from_cache === true
 */
export async function parseSearchQueryCached(query, city, lang, supabase) {
  // Generate cache key (normalized query + lang)
  const normalized = normalizeQuery(query);
  const cacheKey = `parse:${lang}:${normalized}`;

  // Check cache
  const cached = parseCache.get(cacheKey);
  if (cached) {
    return {
      ...cached,
      from_cache: true
    };
  }

  // Parse (hits DB if type matching needed)
  const result = await parseSearchQuery(query, city, lang, supabase);

  // Store in cache
  parseCache.set(cacheKey, result);

  return {
    ...result,
    from_cache: false
  };
}

/**
 * Clears the parse cache
 * Useful for testing or when synonyms are updated
 *
 * @example
 * clearParseCache()
 */
export function clearParseCache() {
  parseCache.clear();
}

/**
 * Gets parse cache stats
 * Useful for monitoring cache effectiveness
 *
 * @returns {object} - Cache statistics
 *
 * @example
 * getParseCacheStats()
 * // Returns: { size: 234, maxSize: 5000, hitRate: 0.73 }
 */
export function getParseCacheStats() {
  return {
    size: parseCache.size,
    maxSize: parseCache.max,
    ttl: parseCache.ttl
  };
}
