import fp from 'fastify-plugin';
import helmet from '@fastify/helmet';

async function securityPlugin(fastify) {
  await fastify.register(helmet, {
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'"],
        imgSrc: ["'self'", "data:", "https:"]
      }
    }
  });

  fastify.addHook('preHandler', async (request, reply) => {
    const routeConfig = request.routeConfig;
    
    if (routeConfig && routeConfig.protected) {
      const apiKey = request.headers['x-api-key'];
      const expectedKey = process.env.API_KEY_PUBLIC;
      
      if (!apiKey || apiKey !== expectedKey) {
        reply.code(401);
        throw new Error('Invalid or missing API key');
      }
    }
  });
}

export default fp(securityPlugin, {
  name: 'security'
});