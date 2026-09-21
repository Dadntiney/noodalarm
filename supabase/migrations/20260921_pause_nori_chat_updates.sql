-- NORI-updateberichten voorlopig niet meer in de chat plaatsen.
-- Welkomstbericht en alarm-redding blijven gewoon werken.
-- release_notes worden wél als "aangekondigd" gemarkeerd zodat ze niet
-- blijven opstapelen; chat-posting staat uit tot we dit weer aanzetten.

create or replace function public.run_update_digest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  n_notes int := 0;
begin
  select count(*)::int into n_notes
  from public.release_notes
  where announced_at is null
    and coalesce(trim(message_nl), '') <> '';

  if n_notes = 0 then
    return jsonb_build_object(
      'ok', true,
      'posted', false,
      'reason', 'nothing_to_announce'
    );
  end if;

  -- Pauzeren: geen alarm_messages insert. Notes wel afronden.
  update public.release_notes
  set announced_at = now()
  where announced_at is null
    and coalesce(trim(message_nl), '') <> '';

  return jsonb_build_object(
    'ok', true,
    'posted', false,
    'reason', 'chat_updates_paused',
    'noteCount', n_notes,
    'groupCount', 0
  );
end;
$$;

revoke all on function public.run_update_digest() from public;

-- Bestaande update-berichten uit de chat verwijderen (welkom + alarm blijven).
delete from public.alarm_messages m
using public.profiles p
where m.sender_id = p.id
  and p.username = 'nori'
  and coalesce(p.is_system, false) = true
  and m.alarm_id is null
  and (
    m.body like '🆕 Update van NORI%'
    or m.body like '🆕 Updates van NORI%'
    or m.body like 'Update van NORI%'
    or m.body like 'Updates van NORI%'
  );
