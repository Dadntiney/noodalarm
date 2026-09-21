-- Systeemaccount NORI als afzender van update-meldingen.
-- (Account wordt live aangemaakt; deze migratie documenteert de digest-logica.)

create or replace function public.run_update_digest()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bullets text[];
  body text;
  n_groups int := 0;
  n_notes int := 0;
  nori_id uuid;
begin
  select id into nori_id from public.profiles where username = 'nori' limit 1;
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
    body := '🆕 Update van NORI' || E'\n\n' || bullets[1];
  else
    body := '🆕 Updates van NORI' || E'\n\n' || (
      select string_agg('• ' || b, E'\n') from unnest(bullets) as b
    );
  end if;

  if char_length(body) > 1000 then
    body := left(body, 1000);
  end if;

  insert into public.alarm_messages (group_id, sender_id, body)
  select g.id, nori_id, body
  from public.alarm_groups g;

  get diagnostics n_groups = row_count;

  update public.release_notes
  set announced_at = now()
  where announced_at is null;

  return jsonb_build_object(
    'ok', true, 'posted', true,
    'noteCount', n_notes, 'groupCount', n_groups, 'sender', 'NORI'
  );
end;
$$;

revoke all on function public.run_update_digest() from public;

create or replace function public.public_user_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint from public.profiles where username <> 'nori';
$$;
