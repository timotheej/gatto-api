import fp from 'fastify-plugin';
import rateLimit from '@fastify/rate-limit';

async function rateLimitPlugin(fastify) {
  await fastify.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
    errorResponseBuilder: (_, context) => {
      return {
        code: 429,
        error: 'Too Many Requests',
        message: `Rate limit exceeded, retry in ${context.ttl}ms`,
        date: Date.now(),
        expiresIn: context.ttl
      };
    }
  });
}

export default fp(rateLimitPlugin, {
  name: 'rateLimit'
});