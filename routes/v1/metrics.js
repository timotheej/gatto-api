import { getMetrics } from '../../utils/searchMetrics.js';

/**
 * Metrics endpoint for monitoring search performance
 * Only accessible with valid API key
 */

export default async function metricsRoutes(fastify) {

  // GET /v1/metrics - Search metrics dashboard
  fastify.get('/metrics', async (request, reply) => {
    try {
      const metrics = getMetrics();

      return reply.send({
        success: true,
        data: metrics,
        timestamp: new Date().toISOString()
      });

    } catch (err) {
      fastify.log.error('GET /metrics error:', err);
      return reply.code(500).send({
        success: false,
        error: 'Failed to fetch metrics',
        timestamp: new Date().toISOString()
      });
    }
  });
}
