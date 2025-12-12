/**
 * Search metrics and monitoring utilities
 * Tracks autocomplete and search performance
 * @module utils/searchMetrics
 */

/**
 * In-memory metrics store
 * Reset on server restart (lightweight solution for V1)
 * For production, consider external monitoring (Datadog, New Relic, etc.)
 */
const metrics = {
  autocomplete: {
    total_requests: 0,
    cache_hits: 0,
    cache_misses: 0,
    errors: 0,
    avg_response_time_ms: 0,
    response_times: [], // Last 100 response times for avg calculation
    popular_queries: new Map(), // Query -> count
  },
  search: {
    total_requests: 0,
    cache_hits: 0,
    cache_misses: 0,
    errors: 0,
    avg_response_time_ms: 0,
    response_times: [],
    name_searches: 0,
    type_searches: 0,
    popular_queries: new Map(),
  }
};

const MAX_RESPONSE_TIMES = 100; // Keep last 100 for moving average
const MAX_POPULAR_QUERIES = 50;  // Track top 50 queries

/**
 * Records an autocomplete request
 * @param {object} params - Request parameters
 * @param {string} params.query - User query
 * @param {boolean} params.cache_hit - Whether response was from cache
 * @param {number} params.response_time_ms - Response time in milliseconds
 * @param {boolean} params.error - Whether request resulted in error
 */
export function recordAutocomplete({ query, cache_hit, response_time_ms, error = false }) {
  const m = metrics.autocomplete;

  m.total_requests++;

  if (cache_hit) {
    m.cache_hits++;
  } else {
    m.cache_misses++;
  }

  if (error) {
    m.errors++;
  }

  // Track response time
  if (response_time_ms !== undefined) {
    m.response_times.push(response_time_ms);
    if (m.response_times.length > MAX_RESPONSE_TIMES) {
      m.response_times.shift(); // Keep only last N
    }
    m.avg_response_time_ms = m.response_times.reduce((a, b) => a + b, 0) / m.response_times.length;
  }

  // Track popular queries
  if (query) {
    const count = m.popular_queries.get(query) || 0;
    m.popular_queries.set(query, count + 1);

    // Limit map size
    if (m.popular_queries.size > MAX_POPULAR_QUERIES * 2) {
      // Sort by count and keep top N
      const sorted = [...m.popular_queries.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, MAX_POPULAR_QUERIES);
      m.popular_queries.clear();
      sorted.forEach(([q, c]) => m.popular_queries.set(q, c));
    }
  }
}

/**
 * Records a search request
 * @param {object} params - Request parameters
 * @param {string} params.query - User query (optional)
 * @param {string} params.mode - Search mode ('name' | 'type' | null)
 * @param {boolean} params.cache_hit - Whether response was from cache
 * @param {number} params.response_time_ms - Response time in milliseconds
 * @param {boolean} params.error - Whether request resulted in error
 */
export function recordSearch({ query, mode, cache_hit, response_time_ms, error = false }) {
  const m = metrics.search;

  m.total_requests++;

  if (cache_hit) {
    m.cache_hits++;
  } else {
    m.cache_misses++;
  }

  if (error) {
    m.errors++;
  }

  // Track search mode
  if (mode === 'name') {
    m.name_searches++;
  } else if (mode === 'type') {
    m.type_searches++;
  }

  // Track response time
  if (response_time_ms !== undefined) {
    m.response_times.push(response_time_ms);
    if (m.response_times.length > MAX_RESPONSE_TIMES) {
      m.response_times.shift();
    }
    m.avg_response_time_ms = m.response_times.reduce((a, b) => a + b, 0) / m.response_times.length;
  }

  // Track popular queries
  if (query) {
    const count = m.popular_queries.get(query) || 0;
    m.popular_queries.set(query, count + 1);

    if (m.popular_queries.size > MAX_POPULAR_QUERIES * 2) {
      const sorted = [...m.popular_queries.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, MAX_POPULAR_QUERIES);
      m.popular_queries.clear();
      sorted.forEach(([q, c]) => m.popular_queries.set(q, c));
    }
  }
}

/**
 * Gets current metrics snapshot
 * @returns {object} - Metrics object
 */
export function getMetrics() {
  return {
    autocomplete: {
      total_requests: metrics.autocomplete.total_requests,
      cache_hit_rate: metrics.autocomplete.total_requests > 0
        ? (metrics.autocomplete.cache_hits / metrics.autocomplete.total_requests * 100).toFixed(2) + '%'
        : '0%',
      error_rate: metrics.autocomplete.total_requests > 0
        ? (metrics.autocomplete.errors / metrics.autocomplete.total_requests * 100).toFixed(2) + '%'
        : '0%',
      avg_response_time_ms: Math.round(metrics.autocomplete.avg_response_time_ms),
      popular_queries: [...metrics.autocomplete.popular_queries.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(([query, count]) => ({ query, count }))
    },
    search: {
      total_requests: metrics.search.total_requests,
      cache_hit_rate: metrics.search.total_requests > 0
        ? (metrics.search.cache_hits / metrics.search.total_requests * 100).toFixed(2) + '%'
        : '0%',
      error_rate: metrics.search.total_requests > 0
        ? (metrics.search.errors / metrics.search.total_requests * 100).toFixed(2) + '%'
        : '0%',
      avg_response_time_ms: Math.round(metrics.search.avg_response_time_ms),
      name_searches: metrics.search.name_searches,
      type_searches: metrics.search.type_searches,
      popular_queries: [...metrics.search.popular_queries.entries()]
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10)
        .map(([query, count]) => ({ query, count }))
    }
  };
}

/**
 * Resets all metrics (useful for testing)
 */
export function resetMetrics() {
  metrics.autocomplete.total_requests = 0;
  metrics.autocomplete.cache_hits = 0;
  metrics.autocomplete.cache_misses = 0;
  metrics.autocomplete.errors = 0;
  metrics.autocomplete.avg_response_time_ms = 0;
  metrics.autocomplete.response_times = [];
  metrics.autocomplete.popular_queries.clear();

  metrics.search.total_requests = 0;
  metrics.search.cache_hits = 0;
  metrics.search.cache_misses = 0;
  metrics.search.errors = 0;
  metrics.search.avg_response_time_ms = 0;
  metrics.search.response_times = [];
  metrics.search.name_searches = 0;
  metrics.search.type_searches = 0;
  metrics.search.popular_queries.clear();
}
