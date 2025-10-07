import fp from 'fastify-plugin';

async function responsesPlugin(fastify) {
  fastify.decorateReply('success', function(data, statusCode = 200) {
    return this.code(statusCode).send({
      success: true,
      data,
      timestamp: new Date().toISOString()
    });
  });

  fastify.decorateReply('error', function(message, statusCode = 400, details = null) {
    return this.code(statusCode).send({
      success: false,
      error: {
        message,
        details,
        timestamp: new Date().toISOString()
      }
    });
  });
}

export default fp(responsesPlugin, {
  name: 'responses'
});