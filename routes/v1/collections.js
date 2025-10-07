async function routes(fastify, options) {
  fastify.get('/collections', async (request, reply) => {
    return reply.success({
      message: 'Collections endpoint - ready for implementation',
      lang: fastify.getLang(request)
    });
  });
}

export default routes;