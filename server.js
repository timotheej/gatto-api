import 'dotenv/config';
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import compress from '@fastify/compress';
import etag from '@fastify/etag';

import supabasePlugin from './plugins/supabase.js';
import corsPlugin from './plugins/cors.js';
import securityPlugin from './plugins/security.js';
import i18nPlugin from './plugins/i18n.js';
import rateLimitPlugin from './plugins/rate-limit.js';
import responsesPlugin from './utils/responses.js';

import v1Routes from './routes/v1/index.js';
import poiRoutes from './routes/v1/poi.js';
import collectionsRoutes from './routes/v1/collections.js';
import homeRoutes from './routes/v1/home.js';

const fastify = Fastify({
  logger: {
    level: process.env.NODE_ENV === 'production' ? 'warn' : 'info'
  }
});

async function build() {
  try {
    await fastify.register(helmet);
    await fastify.register(compress, { 
      global: true,
      encodings: ['gzip', 'deflate', 'br']
    });
    await fastify.register(etag);

    await fastify.register(corsPlugin);
    await fastify.register(securityPlugin);
    await fastify.register(rateLimitPlugin);
    await fastify.register(supabasePlugin);
    await fastify.register(i18nPlugin);
    await fastify.register(responsesPlugin);

    await fastify.register(v1Routes, { prefix: '/v1' });
    await fastify.register(poiRoutes, { prefix: '/v1' });
    await fastify.register(collectionsRoutes, { prefix: '/v1' });
    await fastify.register(homeRoutes, { prefix: '/v1' });

    fastify.get('/health', async (request, reply) => {
      return reply.success({ status: 'healthy' });
    });

    fastify.setNotFoundHandler(async (request, reply) => {
      return reply.error('Route not found', 404);
    });

    fastify.setErrorHandler(async (error, request, reply) => {
      fastify.log.error(error);
      
      if (reply.statusCode === 429) {
        return reply.send(error);
      }
      
      const statusCode = error.statusCode || 500;
      const message = statusCode === 500 ? 'Internal Server Error' : error.message;
      
      return reply.error(message, statusCode);
    });

    return fastify;
  } catch (error) {
    fastify.log.error('Error building server:', error);
    throw error;
  }
}

async function start() {
  try {
    const server = await build();
    const port = process.env.PORT || 3000;
    const host = process.env.NODE_ENV === 'production' ? '0.0.0.0' : 'localhost';
    
    await server.listen({ port, host });
    server.log.info(`🚀 Server running at http://${host}:${port}`);
    server.log.info(`📚 API v1 available at http://${host}:${port}/v1`);
  } catch (error) {
    console.error('Error starting server:', error);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  start();
}

export { build, start };