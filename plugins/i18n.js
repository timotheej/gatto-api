import fp from 'fastify-plugin';

async function i18nPlugin(fastify) {
  fastify.addHook('preHandler', async (request, reply) => {
    const lang = request.query.lang;
    const supportedLangs = ['fr', 'en'];
    
    request.lang = supportedLangs.includes(lang) ? lang : 'fr';
  });

  fastify.decorate('getLang', function(request) {
    return request.lang || 'fr';
  });
}

export default fp(i18nPlugin, {
  name: 'i18n'
});