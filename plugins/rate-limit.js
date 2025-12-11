import fp from 'fastify-plugin';
import rateLimit from '@fastify/rate-limit';

async function rateLimitPlugin(fastify) {
  await fastify.register(rateLimit, {
    max: 60, // Increased from 30 to 60 requests per minute
    timeWindow: '1 minute',
    cache: 10000, // Cache 10k IPs
    allowList: process.env.NODE_ENV === 'development' ? ['127.0.0.1', '::1'] : [],
    errorResponseBuilder: (_, context) => {
      return {
        code: 429,
        error: 'Too Many Requests',
        message: `Rate limit exceeded (${context.max} requests per minute). Retry in ${Math.ceil(context.ttl / 1000)} seconds`,
        date: Date.now(),
        expiresIn: context.ttl
      };
    }
  });
}

export default fp(rateLimitPlugin, {
  name: 'rateLimit'
});