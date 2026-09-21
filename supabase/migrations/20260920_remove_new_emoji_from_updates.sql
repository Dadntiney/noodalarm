-- Geen standaard-emoji's (zoals 🆕) meer in NORI-updateberichten.
-- Titel blijft platte tekst; de UI-badge "Update" is genoeg.

create or replace function public.run_update_digest()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  bullets text[];
  body text;
  n_groups int := 0;
  n_notes int := 0;
  nori_id uuid;
begin
  nori_id := public.nori_system_user_id();
  if nori_id is null then
    return jsonb_build_object('ok', false, 'error', 'NORI system user missing');
  end if;

  select coalesce(array_agg(trim(message_nl) order by id), '{}')
  into bullets
  from public.release_notes
  where announced_at is null
    and coalesce(trim(message_nl), '') <> '';

  n_notes := coalesce(array_length(bullets, 1), 0);
  if n_notes = 0 then
    return jsonb_build_object('ok', true, 'posted', false, 'reason', 'nothing_to_announce');
  end if;

  if n_notes = 1 then
    body := 'Update van NORI' || E'\n\n' || bullets[1];
  else
    body := 'Updates van NORI' || E'\n\n' || (
      select string_agg('• ' || b, E'\n') from unnest(bullets) as b
    );
  end if;

  if char_length(body) > 1000 then
    body := left(body, 1000);
  end if;

  insert into public.alarm_messages (group_id, sender_id, body)
  select g.id, nori_id, body
  from public.alarm_groups g
  join public.profiles p on p.id = g.owner_id
  where coalesce(p.is_system, false) = false;

  get diagnostics n_groups = row_count;

  update public.release_notes
  set announced_at = now()
  where announced_at is null;

  return jsonb_build_object(
    'ok', true, 'posted', true,
    'noteCount', n_notes, 'groupCount', n_groups, 'sender', 'NORI'
  );
end;
$function$;

-- Bestaande update-berichten: emoji verwijderen.
update public.alarm_messages
set body = regexp_replace(body, '^🆕\s*', '')
where body like '🆕%';

-- Welkomsttekst zonder zwaai/hart-emoji.
create or replace function public.nori_welcome_message_body()
returns text
language sql
immutable
as $function$
  select $msg$Welkom bij NORI!

Vanaf vandaag zijn jullie samen verbonden in deze groep. NORI is er om jullie te helpen, belangrijke updates te delen en ervoor te zorgen dat jullie op de hoogte blijven.

Ik wens jullie veel plezier met NORI en vooral veel fijne momenten samen.

Welkom bij NORI!$msg$::text;
$function$;

update public.alarm_messages
set body = public.nori_welcome_message_body()
where body like E'👋 Welkom bij NORI!%';
