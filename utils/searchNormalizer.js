/**
 * Search query normalization and validation utilities
 * @module utils/searchNormalizer
 */

/**
 * Normalizes a search query for consistent matching
 * - Converts to lowercase
 * - Removes accents (é → e, à → a, etc.)
 * - Normalizes ligatures (œ → oe, æ → ae)
 * - Normalizes apostrophes (' and ' → ')
 * - Trims whitespace
 *
 * @param {string} query - Raw search query
 * @returns {string} - Normalized query
 *
 * @example
 * normalizeQuery("Café de l'Opéra")
 * // Returns: "cafe de l'opera"
 *
 * normalizeQuery("Bœuf Bourguignon")
 * // Returns: "boeuf bourguignon"
 */
export function normalizeQuery(query) {
  if (!query || typeof query !== 'string') {
    return '';
  }

  return query
    .toLowerCase()
    .normalize('NFD')  // Decompose accented characters (é → e + accent)
    .replace(/[\u0300-\u036f]/g, '')  // Remove accent marks
    .replace(/œ/g, 'oe')  // Normalize ligatures
    .replace(/æ/g, 'ae')
    .replace(/['']/g, "'")  // Normalize apostrophes (U+2019, U+2018 → U+0027)
    .trim();
}

/**
 * Calculates an adaptive similarity threshold based on query length
 * Short queries require stricter matching to avoid false positives
 *
 * @param {string} query - Search query (normalized or not)
 * @returns {number} - Similarity threshold (0-1)
 *
 * @example
 * getAdaptiveSimilarityThreshold("a")
 * // Returns: 0.9 (very strict for 1-2 chars)
 *
 * getAdaptiveSimilarityThreshold("restaurant italien")
 * // Returns: 0.3 (permissive for long queries)
 */
export function getAdaptiveSimilarityThreshold(query) {
  if (!query) return 0.3;

  const len = query.length;

  // Very strict for 1-2 characters (prevent matching "a" with "La Maison")
  if (len <= 2) return 0.9;

  // Strict for 3-4 characters
  if (len <= 4) return 0.6;

  // Medium for 5-8 characters
  if (len <= 8) return 0.4;

  // Permissive for 9+ characters
  return 0.3;
}

/**
 * Validates a search query
 * Checks length, characters, and basic sanity
 *
 * @param {string} query - Search query to validate
 * @returns {{valid: boolean, error?: string}} - Validation result
 *
 * @example
 * validateQuery("a")
 * // Returns: { valid: false, error: "Query must be at least 2 characters" }
 *
 * validateQuery("restaurant italien")
 * // Returns: { valid: true }
 */
export function validateQuery(query) {
  if (!query || typeof query !== 'string') {
    return {
      valid: false,
      error: 'Query is required and must be a string'
    };
  }

  // Trim for validation
  const trimmed = query.trim();

  // Minimum length: 2 characters
  if (trimmed.length < 2) {
    return {
      valid: false,
      error: 'Query must be at least 2 characters'
    };
  }

  // Maximum length: 200 characters (prevent abuse)
  if (trimmed.length > 200) {
    return {
      valid: false,
      error: 'Query must be less than 200 characters'
    };
  }

  // Allowed characters: letters (with accents), numbers, spaces, hyphens, apostrophes
  // Regex matches: a-zA-Z, numbers, French accented chars, spaces, -, '
  const validPattern = /^[a-zA-Z0-9àâäéèêëïîôùûüÿçœæÀÂÄÉÈÊËÏÎÔÙÛÜŸÇŒÆ\s\-']+$/;

  if (!validPattern.test(trimmed)) {
    return {
      valid: false,
      error: 'Query contains invalid characters. Only letters, numbers, spaces, hyphens, and apostrophes are allowed.'
    };
  }

  return { valid: true };
}

/**
 * Sanitizes a query for safe processing
 * Combines validation + normalization
 *
 * @param {string} query - Raw query
 * @returns {{valid: boolean, normalized?: string, error?: string}} - Sanitized result
 *
 * @example
 * sanitizeQuery("  Café Italien!  ")
 * // Returns: { valid: true, normalized: "cafe italien" }
 */
export function sanitizeQuery(query) {
  const validation = validateQuery(query);

  if (!validation.valid) {
    return validation;
  }

  return {
    valid: true,
    normalized: normalizeQuery(query)
  };
}
