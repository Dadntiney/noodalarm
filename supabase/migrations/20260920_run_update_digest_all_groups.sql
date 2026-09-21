-- Digest voortaan via Postgres (alle groepen), niet alleen edge function.
-- Cron job nori-daily-update-digest roept deze functie aan.

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
begin
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
      select string_agg('• ' || b, E'\n')
      from unnest(bullets) as b
    );
  end if;

  -- alarm_messages_body_check: 1..1000 tekens
  if char_length(body) > 1000 then
    body := left(body, 1000);
  end if;

  insert into public.alarm_messages (group_id, sender_id, body)
  select g.id, g.owner_id, body
  from public.alarm_groups g
  where g.owner_id is not null;

  get diagnostics n_groups = row_count;

  update public.release_notes
  set announced_at = now()
  where announced_at is null;

  return jsonb_build_object(
    'ok', true,
    'posted', true,
    'noteCount', n_notes,
    'groupCount', n_groups
  );
end;
$$;

revoke all on function public.run_update_digest() from public;
