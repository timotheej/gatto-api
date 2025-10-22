const startTime = Date.now();

async function routes(fastify, options) {
  fastify.get("/", async (request, reply) => {
    const uptime = Date.now() - startTime;

    return reply.success({
      status: "ok",
      version: "1.0",
      endpoints: ["/v1/poi", "/v1/collections", "/v1/home", "/v1/sitemap/pois"],
      uptime: Math.floor(uptime / 1000),
    });
  });
}

export default routes;
