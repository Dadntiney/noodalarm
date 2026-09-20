// NORI — dagelijkse update-samenvatting naar Danny's groepschat.
//
// Getriggerd via pg_cron om 08:00 UTC (job: nori-daily-update-digest).
// Bundelt alle rijen in public.release_notes met announced_at IS NULL tot
// één vriendelijk, niet-technisch bericht. Op stille dagen (geen rijen)
// gebeurt er niets — geen lege chatbubbel.
//
// Vereiste secrets / env:
//   SUPABASE_URL
//   SUPABASE_SERVICE_ROLE_KEY
//   DIGEST_GROUP_ID   — alarm_groups.id van Danny's kring
//   DIGEST_SENDER_ID  — auth.users.id die als afzender fungeert (Danny)

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
    const groupId = Deno.env.get('DIGEST_GROUP_ID');
    const senderId = Deno.env.get('DIGEST_SENDER_ID');

    if (!supabaseUrl || !serviceKey || !groupId || !senderId) {
      return json({ error: 'Missing DIGEST_GROUP_ID / DIGEST_SENDER_ID or Supabase secrets' }, 500);
    }

    const sb = createClient(supabaseUrl, serviceKey);

    const { data: notes, error: notesErr } = await sb
      .from('release_notes')
      .select('id, message_nl')
      .is('announced_at', null)
      .order('id', { ascending: true });

    if (notesErr) return json({ error: notesErr.message }, 500);

    // Stille dag: niets posten, niets markeren.
    if (!notes || notes.length === 0) {
      return json({ ok: true, posted: false, reason: 'nothing_to_announce' });
    }

    const bullets = notes
      .map((n) => (n.message_nl || '').trim())
      .filter((m) => m.length > 0);

    if (bullets.length === 0) {
      return json({ ok: true, posted: false, reason: 'empty_messages' });
    }

    const body =
      bullets.length === 1
        ? `🆕 Update van NORI\n\n${bullets[0]}`
        : `🆕 Updates van NORI\n\n${bullets.map((b) => `• ${b}`).join('\n')}`;

    // alarm_messages_body_check eist minstens body of media_path — body
    // mag dus nooit null/leeg zijn. Trim + expliciete check hierboven.
    const { error: insertErr } = await sb.from('alarm_messages').insert({
      group_id: groupId,
      sender_id: senderId,
      body,
    });

    if (insertErr) return json({ error: insertErr.message }, 500);

    const ids = notes.map((n) => n.id);
    const { error: markErr } = await sb
      .from('release_notes')
      .update({ announced_at: new Date().toISOString() })
      .in('id', ids);

    if (markErr) return json({ error: markErr.message }, 500);

    return json({ ok: true, posted: true, count: bullets.length });
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
