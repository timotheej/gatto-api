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
  
  // Combine origins based on environment
  let corsOrigins = defaultOrigins;
  
  if (process.env.CORS_ORIGIN) {
    corsOrigins = process.env.CORS_ORIGIN.split(',');
  } else if (process.env.NODE_ENV !== 'production') {
    // In development, allow both local and production origins
    corsOrigins = [...defaultOrigins, ...localOrigins];
  }
  
  console.log('🔧 CORS Configuration:', {
    NODE_ENV: process.env.NODE_ENV,
    corsOrigins,
    localOrigins
  });
  
  await fastify.register(cors, {
    origin: process.env.NODE_ENV === 'development' ? true : corsOrigins, // Allow all origins in dev
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key']
  });
}

export default fp(corsPlugin, {
  name: 'cors'
});