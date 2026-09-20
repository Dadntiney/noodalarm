// NORI — dagelijkse update-samenvatting naar élke gebruikers-groepschat.
//
// Getriggerd via pg_cron om 08:00 UTC (job: nori-daily-update-digest).
// Bundelt alle rijen in public.release_notes met announced_at IS NULL tot
// één vriendelijk, niet-technisch bericht en post dat in elke alarm_group
// (afzender = groeps-eigenaar). Op stille dagen gebeurt er niets.
//
// Vereiste secrets / env:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   DIGEST_SENDER_ID — optioneel fallback-afzender als een groep geen owner heeft

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
    const fallbackSenderId = Deno.env.get('DIGEST_SENDER_ID');

    if (!supabaseUrl || !serviceKey) {
      return json({ error: 'Missing Supabase secrets' }, 500);
    }

    const sb = createClient(supabaseUrl, serviceKey);

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

    if (bullets.length === 0) {
      return json({ ok: true, posted: false, reason: 'empty_messages' });
    }

    let body =
      bullets.length === 1
        ? `🆕 Update van NORI\n\n${bullets[0]}`
        : `🆕 Updates van NORI\n\n${bullets.map((b) => `• ${b}`).join('\n')}`;
    // alarm_messages_body_check: 1..1000 tekens
    if (body.length > 1000) body = body.slice(0, 1000);

    const { data: groups, error: groupsErr } = await sb
      .from('alarm_groups')
      .select('id, owner_id');

    if (groupsErr) return json({ error: groupsErr.message }, 500);
    if (!groups || groups.length === 0) {
      return json({ ok: true, posted: false, reason: 'no_groups' });
    }

    const rows = groups
      .map((g) => ({
        group_id: g.id,
        sender_id: g.owner_id || fallbackSenderId,
        body,
      }))
      .filter((r) => !!r.sender_id);

    if (!rows.length) {
      return json({ error: 'No valid sender for any group (set DIGEST_SENDER_ID)' }, 500);
    }

    const { error: insertErr } = await sb.from('alarm_messages').insert(rows);
    if (insertErr) return json({ error: insertErr.message }, 500);

    const ids = notes.map((n) => n.id);
    const { error: markErr } = await sb
      .from('release_notes')
      .update({ announced_at: new Date().toISOString() })
      .in('id', ids);

    if (markErr) return json({ error: markErr.message }, 500);

    return json({
      ok: true,
      posted: true,
      noteCount: bullets.length,
      groupCount: rows.length,
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
