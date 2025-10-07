import fp from 'fastify-plugin';
import cors from '@fastify/cors';

async function corsPlugin(fastify) {
  const corsOrigins = process.env.CORS_ORIGIN?.split(',') || ['https://gatto.city', 'https://www.gatto.city'];
  
  await fastify.register(cors, {
    origin: corsOrigins,
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key']
  });
}

export default fp(corsPlugin, {
  name: 'cors'
});