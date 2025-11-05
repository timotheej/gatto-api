import fp from 'fastify-plugin';
import cors from '@fastify/cors';

async function corsPlugin(fastify) {
  // Default production origins
  const defaultOrigins = ['https://gatto.city', 'https://www.gatto.city'];
  
  // Add local development origins
  const localOrigins = [
    'http://localhost:3000',    // Next.js dev server
    'http://localhost:3001',    // Alternative dev port
    'http://127.0.0.1:3000',    // Localhost alternative
    'http://127.0.0.1:3001'     // Alternative
  ];
  
  // Combine origins based on environment (always use whitelist)
  const allowedOrigins = process.env.CORS_ORIGIN
    ? process.env.CORS_ORIGIN.split(',')
    : process.env.NODE_ENV !== 'production'
      ? [...defaultOrigins, ...localOrigins]
      : defaultOrigins;

  // Use logger instead of console.log
  fastify.log.debug({ allowedOrigins }, 'CORS configured');

  await fastify.register(cors, {
    origin: allowedOrigins, // Always use whitelist, never `true`
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key']
  });
}

export default fp(corsPlugin, {
  name: 'cors'
});