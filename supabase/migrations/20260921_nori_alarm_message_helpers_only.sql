-- Bij een écht noodalarm: NORI-bericht met locatie + reddingskaart ALLEEN
-- naar noodcontacten (niet in de chat van de activator).
-- Oefenalarm: alleen in de groep van de activator (contacten merken niets).

create or replace function public.post_nori_alarm_rescue_message(p_alarm_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  v_nori uuid;
  v_body text;
  v_msg_id uuid;
  v_first uuid;
  r record;
begin
  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    raise exception 'Alarm niet gevonden';
  end if;

  if auth.uid() is not null and auth.uid() <> a.triggered_by then
    raise exception 'Niet toegestaan';
  end if;

  -- Idempotent: één set NORI-berichten per alarm.
  select id into v_msg_id
  from public.alarm_messages
  where alarm_id = p_alarm_id
    and sender_id = public.nori_system_user_id()
  limit 1;
  if v_msg_id is not null then
    return v_msg_id;
  end if;

  v_nori := public.nori_system_user_id();
  v_body := public.nori_alarm_rescue_message_body(p_alarm_id);
  if v_body is null or char_length(v_body) < 1 then
    return null;
  end if;

  if coalesce(a.test_mode, false) then
    -- Oefenen: alleen activator ziet het bericht (1-op-1 preview).
    insert into public.alarm_messages (group_id, sender_id, body, alarm_id)
    values (a.group_id, v_nori, v_body, p_alarm_id)
    returning id into v_first;
    return v_first;
  end if;

  -- Echt alarm: alleen naar elk noodcontact — niet naar de activator.
  for r in
    select g.id as group_id
    from public.connections c
    join public.alarm_groups g on g.owner_id = case
      when c.requester_id = a.triggered_by then c.target_id
      else c.requester_id
    end
    where c.status = 'accepted'
      and (c.requester_id = a.triggered_by or c.target_id = a.triggered_by)
      and g.id is distinct from a.group_id
  loop
    insert into public.alarm_messages (group_id, sender_id, body, alarm_id)
    values (r.group_id, v_nori, v_body, p_alarm_id)
    returning id into v_first;
  end loop;

  return v_first;
end;
$$;

revoke all on function public.post_nori_alarm_rescue_message(uuid) from public;
grant execute on function public.post_nori_alarm_rescue_message(uuid) to authenticated;
