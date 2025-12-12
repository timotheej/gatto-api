/**
 * Type synonym matching utilities
 * Maps natural language queries to type_keys via detection_keywords in poi_types
 * @module utils/searchSynonyms
 */

/**
 * Finds type_keys matching a keyword
 * Uses detection_keywords_fr/en arrays in poi_types table
 *
 * @param {string} word - Word to search (will be lowercased)
 * @param {string} lang - Language (fr|en)
 * @param {object} supabase - Supabase client
 * @returns {Promise<string[]>} - Array of matching type_keys
 *
 * @example
 * await findTypesBySynonym('italien', 'fr', supabase)
 * // Returns: ['italian_restaurant']
 *
 * await findTypesBySynonym('sushi', 'fr', supabase)
 * // Returns: ['japanese_restaurant']
 */
export async function findTypesBySynonym(word, lang, supabase) {
  if (!word || typeof word !== 'string') {
    return [];
  }

  const normalized = word.toLowerCase().trim();
  const keywordColumn = lang === 'en' ? 'detection_keywords_en' : 'detection_keywords_fr';

  // Query poi_types where detection_keywords array contains the word
  const { data, error } = await supabase
    .from('poi_types')
    .select('type_key')
    .eq('is_active', true)
    .contains(keywordColumn, [normalized]);

  if (error) {
    console.error('Error finding types by keyword:', error);
    return [];
  }

  if (!data || data.length === 0) {
    return [];
  }

  return data.map(row => row.type_key);
}

/**
 * Finds type_keys by searching in type labels (fallback)
 * Uses ILIKE pattern matching on poi_types table
 *
 * @param {string} query - Query to search in labels
 * @param {string} lang - Language (fr|en)
 * @param {object} supabase - Supabase client
 * @returns {Promise<string[]>} - Array of matching type_keys
 *
 * @example
 * await findTypesByLabel('restaurant', 'fr', supabase)
 * // Returns: ['italian_restaurant', 'french_restaurant', ...]
 */
export async function findTypesByLabel(query, lang, supabase) {
  if (!query || typeof query !== 'string') {
    return [];
  }

  const labelCol = lang === 'en' ? 'label_en' : 'label_fr';

  const { data, error } = await supabase
    .from('poi_types')
    .select('type_key')
    .eq('is_active', true)
    .ilike(labelCol, `%${query}%`)
    .limit(10);

  if (error) {
    console.error('Error finding types by label:', error);
    return [];
  }

  if (!data) {
    return [];
  }

  return data.map(row => row.type_key);
}

/**
 * Intelligent type matching (synonyms first, then labels)
 * Tries exact synonym match first, then falls back to label search
 *
 * @param {string} query - Query to match
 * @param {string} lang - Language (fr|en)
 * @param {object} supabase - Supabase client
 * @returns {Promise<string[]>} - Array of matching type_keys
 *
 * @example
 * // Exact synonym match
 * await matchTypes('italien', 'fr', supabase)
 * // Returns: ['italian_restaurant']
 *
 * // Label fallback
 * await matchTypes('cuisine italienne', 'fr', supabase)
 * // Returns: ['italian_restaurant'] (via label search)
 *
 * // No match
 * await matchTypes('xyz123', 'fr', supabase)
 * // Returns: []
 */
export async function matchTypes(query, lang, supabase) {
  if (!query) {
    return [];
  }

  const normalized = query.toLowerCase().trim();

  // 1. Try exact synonym match first (fast, precise)
  let typeKeys = await findTypesBySynonym(normalized, lang, supabase);

  if (typeKeys.length > 0) {
    return typeKeys;
  }

  // 2. Fallback: search in type labels (slower, broader)
  typeKeys = await findTypesByLabel(normalized, lang, supabase);

  return typeKeys;
}

/**
 * Checks if a query matches a known type synonym or label
 * Returns boolean without fetching actual types (lighter check)
 *
 * @param {string} query - Query to check
 * @param {string} lang - Language (fr|en)
 * @param {object} supabase - Supabase client
 * @returns {Promise<boolean>} - True if matches a type
 *
 * @example
 * await isKnownType('italien', 'fr', supabase)
 * // Returns: true
 *
 * await isKnownType('xyz123', 'fr', supabase)
 * // Returns: false
 */
export async function isKnownType(query, lang, supabase) {
  const types = await matchTypes(query, lang, supabase);
  return types.length > 0;
}
