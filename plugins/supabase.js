import { createClient } from '@supabase/supabase-js';
import fp from 'fastify-plugin';

async function supabasePlugin(fastify) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be provided');
  }

  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  fastify.decorate('supabase', supabase);
}

export default fp(supabasePlugin, {
  name: 'supabase'
});