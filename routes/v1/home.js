async function routes(fastify, options) {
  fastify.get('/home', async (request, reply) => {
    return reply.success({
      message: 'Home endpoint - ready for implementation',
      lang: fastify.getLang(request)
    });
  });
}

export default routes;