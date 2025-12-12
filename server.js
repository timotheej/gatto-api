import "dotenv/config";
import Fastify from "fastify";
import helmet from "@fastify/helmet";
import compress from "@fastify/compress";
import etag from "@fastify/etag";

import supabasePlugin from "./plugins/supabase.js";
import corsPlugin from "./plugins/cors.js";
import securityPlugin from "./plugins/security.js";
import i18nPlugin from "./plugins/i18n.js";
import rateLimitPlugin from "./plugins/rate-limit.js";
import responsesPlugin from "./utils/responses.js";

import v1Routes from "./routes/v1/index.js";
import poisRoutes from "./routes/v1/pois.js";
import poisFacetsRoutes from "./routes/v1/pois/facets.js";
import autocompleteRoutes from "./routes/v1/autocomplete.js";
import metricsRoutes from "./routes/v1/metrics.js";
import collectionsRoutes from "./routes/v1/collections.js";
import homeRoutes from "./routes/v1/home.js";
import sitemapRoutes from "./routes/v1/sitemap.js";

const fastify = Fastify({
  logger: {
    level: process.env.NODE_ENV === "production" ? "warn" : "info",
  },
  connectionTimeout: 10000, // 10s connection timeout
  keepAliveTimeout: 5000,
  requestTimeout: 30000, // 30s max per request
  bodyLimit: 1048576, // 1MB max body size
});

async function build() {
  try {
    await fastify.register(helmet);
    await fastify.register(compress, {
      global: true,
      encodings: ["gzip", "deflate", "br"],
    });
    await fastify.register(etag);

    await fastify.register(corsPlugin);
    await fastify.register(securityPlugin);
    await fastify.register(rateLimitPlugin);
    await fastify.register(supabasePlugin);
    await fastify.register(i18nPlugin);
    await fastify.register(responsesPlugin);

    // Global API key authentication
    fastify.addHook('onRequest', async (request, reply) => {
      // Public routes whitelist
      const publicRoutes = ['/health', '/v1', '/'];

      // Allow public routes
      if (publicRoutes.includes(request.url) || request.url === '/') {
        return;
      }

      // Verify API key for all other routes
      const apiKey = request.headers['x-api-key'];
      const validKey = process.env.API_KEY_PUBLIC;

      if (!validKey) {
        fastify.log.error('API_KEY_PUBLIC not configured');
        return reply.code(500).send({
          success: false,
          error: 'Server configuration error',
          timestamp: new Date().toISOString()
        });
      }

      if (!apiKey || apiKey !== validKey) {
        fastify.log.warn({
          ip: request.ip,
          url: request.url,
          userAgent: request.headers['user-agent']
        }, 'Unauthorized access attempt');

        return reply.code(401).send({
          success: false,
          error: 'Unauthorized - Invalid or missing API key',
          timestamp: new Date().toISOString()
        });
      }

      // Valid API key, log for security monitoring
      fastify.log.debug({ url: request.url }, 'Authenticated request');
    });

    // Security monitoring - log suspicious activity
    fastify.addHook('onResponse', async (request, reply) => {
      // Log unauthorized access attempts
      if (reply.statusCode === 401 || reply.statusCode === 403) {
        fastify.log.warn({
          ip: request.ip,
          url: request.url,
          userAgent: request.headers['user-agent'],
          statusCode: reply.statusCode,
          responseTime: reply.getResponseTime()
        }, 'Security: Unauthorized access attempt');
      }

      // Log server errors for investigation
      if (reply.statusCode >= 500) {
        fastify.log.error({
          ip: request.ip,
          url: request.url,
          statusCode: reply.statusCode,
          responseTime: reply.getResponseTime()
        }, 'Security: Server error occurred');
      }
    });

    await fastify.register(v1Routes, { prefix: "/v1" });

    // POI routes
    await fastify.register(poisRoutes, { prefix: "/v1" });
    await fastify.register(poisFacetsRoutes);

    // Autocomplete route
    await fastify.register(autocompleteRoutes, { prefix: "/v1" });

    // Metrics route (monitoring)
    await fastify.register(metricsRoutes, { prefix: "/v1" });

    await fastify.register(collectionsRoutes, { prefix: "/v1" });
    await fastify.register(homeRoutes, { prefix: "/v1" });
    await fastify.register(sitemapRoutes, { prefix: "/v1" });

    fastify.get("/health", async (request, reply) => {
      return reply.success({ status: "healthy" });
    });

    fastify.setNotFoundHandler(async (request, reply) => {
      return reply.error("Route not found", 404);
    });

    fastify.setErrorHandler(async (error, request, reply) => {
      fastify.log.error(error);

      if (reply.statusCode === 429) {
        return reply.send(error);
      }

      const statusCode = error.statusCode || 500;
      const message =
        statusCode === 500 ? "Internal Server Error" : error.message;

      return reply.error(message, statusCode);
    });

    return fastify;
  } catch (error) {
    fastify.log.error("Error building server:", error);
    throw error;
  }
}

async function start() {
  try {
    const server = await build();
    const port = process.env.PORT || 3000;
    const host =
      process.env.NODE_ENV === "production" ? "0.0.0.0" : "localhost";

    await server.listen({ port, host });
    server.log.info(`🚀 Server running at http://${host}:${port}`);
    server.log.info(`📚 API v1 available at http://${host}:${port}/v1`);
  } catch (error) {
    console.error("Error starting server:", error);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  start();
}

export { build, start };
