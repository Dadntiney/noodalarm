// NORI — dagelijkse update-samenvatting naar élke gebruikers-groepschat.
//
// Primair pad is Postgres: public.run_update_digest() via pg_cron
// (job: nori-daily-update-digest, 08:00 UTC). Deze edge function is
// legacy/fallback en moet dezelfde regels volgen:
//   - afzender = systeemprofiel NORI (is_system)
//   - niet posten in NORI’s eigen alarm_group
//   - body 1..1000 tekens
//
// Vereiste secrets / env:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceKey) {
      return json({ error: 'Missing Supabase secrets' }, 500);
    }

    const sb = createClient(supabaseUrl, serviceKey);

    // Canonieke implementatie in Postgres.
    const { data: digestResult, error: digestErr } = await sb.rpc('run_update_digest');
    if (!digestErr) return json(digestResult ?? { ok: true });

    // Fallback als RPC onverwacht ontbreekt.
    const { data: noriProfile, error: noriErr } = await sb
      .from('profiles')
      .select('id')
      .eq('username', 'nori')
      .eq('is_system', true)
      .maybeSingle();
    if (noriErr) return json({ error: noriErr.message }, 500);
    const noriId = noriProfile?.id;
    if (!noriId) return json({ error: 'NORI system user missing', rpc: digestErr.message }, 500);

    const { data: notes, error: notesErr } = await sb
      .from('release_notes')
      .select('id, message_nl')
      .is('announced_at', null)
      .order('id', { ascending: true });
    if (notesErr) return json({ error: notesErr.message }, 500);
    if (!notes || notes.length === 0) {
      return json({ ok: true, posted: false, reason: 'nothing_to_announce' });
    }

    const bullets = notes
      .map((n) => (n.message_nl || '').trim())
      .filter((m) => m.length > 0);
    if (!bullets.length) {
      return json({ ok: true, posted: false, reason: 'empty_messages' });
    }

    let body =
      bullets.length === 1
        ? `🆕 Update van NORI\n\n${bullets[0]}`
        : `🆕 Updates van NORI\n\n${bullets.map((b) => `• ${b}`).join('\n')}`;
    if (body.length > 1000) body = body.slice(0, 1000);

    const { data: systemProfiles } = await sb.from('profiles').select('id').eq('is_system', true);
    const skipOwners = new Set((systemProfiles || []).map((p) => p.id));

    const { data: groups, error: groupsErr } = await sb.from('alarm_groups').select('id, owner_id');
    if (groupsErr) return json({ error: groupsErr.message }, 500);

    const rows = (groups || [])
      .filter((g) => g.owner_id && !skipOwners.has(g.owner_id))
      .map((g) => ({ group_id: g.id, sender_id: noriId, body }));
    if (!rows.length) return json({ ok: true, posted: false, reason: 'no_groups' });

    const { error: insertErr } = await sb.from('alarm_messages').insert(rows);
    if (insertErr) return json({ error: insertErr.message }, 500);

    const { error: markErr } = await sb
      .from('release_notes')
      .update({ announced_at: new Date().toISOString() })
      .in('id', notes.map((n) => n.id));
    if (markErr) return json({ error: markErr.message }, 500);

    return json({
      ok: true,
      posted: true,
      noteCount: bullets.length,
      groupCount: rows.length,
      sender: 'NORI',
      fallback: true,
      rpcError: digestErr.message,
    });
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 500);
  }
});

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
