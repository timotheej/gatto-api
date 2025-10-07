import { createClient } from '@supabase/supabase-js';
import fp from 'fastify-plugin';

async function supabasePlugin(fastify) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error('SUPABASE_URL and SUPABASE_ANON_KEY must be provided');
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);

  fastify.decorate('supabase', supabase);
}

export default fp(supabasePlugin, {
  name: 'supabase'
});