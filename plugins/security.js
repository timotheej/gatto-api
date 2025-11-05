import fp from 'fastify-plugin';
import helmet from '@fastify/helmet';

async function securityPlugin(fastify) {
  // Enhanced security headers with Helmet
  await fastify.register(helmet, {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'"], // Removed unsafe-inline
        scriptSrc: ["'self'"],
        imgSrc: [
          "'self'",
          "data:",
          "https://cuwrsdssoonlwypboarg.supabase.co" // Specific CDN only
        ],
        connectSrc: [
          "'self'",
          "https://cuwrsdssoonlwypboarg.supabase.co"
        ]
      }
    },
    frameguard: {
      action: 'deny' // Prevent clickjacking
    },
    noSniff: true, // X-Content-Type-Options: nosniff
    hsts: {
      maxAge: 31536000, // 1 year
      includeSubDomains: true,
      preload: true
    },
    referrerPolicy: {
      policy: 'strict-origin-when-cross-origin'
    }
  });

  // API key validation (no dev bypass)
  fastify.addHook('preHandler', async (request, reply) => {
    const routeConfig = request.routeOptions?.config;

    if (routeConfig && routeConfig.protected) {
      const apiKey = request.headers['x-api-key'];
      const expectedKey = process.env.API_KEY_PUBLIC;

      if (!expectedKey) {
        fastify.log.error('API_KEY_PUBLIC not configured');
        reply.code(500);
        throw new Error('Server configuration error');
      }

      if (!apiKey || apiKey !== expectedKey) {
        fastify.log.warn({
          ip: request.ip,
          url: request.url
        }, 'Unauthorized access attempt');

        reply.code(401);
        throw new Error('Invalid or missing API key');
      }
    }
  });
}

export default fp(securityPlugin, {
  name: 'security'
});