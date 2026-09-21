-- Compact NORI-alarmbericht: alleen korte tekst + link naar locatie
-- en reddingskaart (nori-rescue:<alarm_id>). Geen medische dump in de chat.
-- test_mode: alleen in de groep van de activator (contacten merken niets).
-- get_alarm_rescue_card: overlay-inhoud voor wie de link mag openen.

create or replace function public.nori_alarm_rescue_message_body(p_alarm_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a record;
  v_name text;
  v_body text;
  v_maps text;
begin
  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    return null;
  end if;

  select full_name into v_name from public.profiles where id = a.triggered_by;
  v_name := coalesce(nullif(trim(v_name), ''), 'Iemand');

  v_body := '🚨 Alarm van ' || v_name || E'\n\n';
  v_body := v_body || 'Tik op een knop hieronder:' || E'\n';

  if a.lat is not null and a.lng is not null then
    v_maps := 'https://www.google.com/maps/search/?api=1&query=' || a.lat::text || ',' || a.lng::text;
    v_body := v_body || E'\n📍 ' || v_maps;
  end if;

  v_body := v_body || E'\n🩺 nori-rescue:' || a.id::text;

  if char_length(v_body) > 1000 then
    v_body := left(v_body, 997) || '…';
  end if;
  return v_body;
end;
$$;

revoke all on function public.nori_alarm_rescue_message_body(uuid) from public;

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

  insert into public.alarm_messages (group_id, sender_id, body, alarm_id)
  values (a.group_id, v_nori, v_body, p_alarm_id)
  returning id into v_first;

  -- Echt alarm: ook naar elk noodcontact. Oefenalarm: alleen activator.
  if not coalesce(a.test_mode, false) then
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
      values (r.group_id, v_nori, v_body, p_alarm_id);
    end loop;
  end if;

  return v_first;
end;
$$;

revoke all on function public.post_nori_alarm_rescue_message(uuid) from public;
grant execute on function public.post_nori_alarm_rescue_message(uuid) to authenticated;

-- Reddingskaart via link in het NORI-bericht (geen grote kaart in de chat).
create or replace function public.get_alarm_rescue_card(p_alarm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a record;
  v_uid uuid := auth.uid();
  v_name text;
  v_allowed boolean := false;
  m jsonb;
  p jsonb;
begin
  if v_uid is null then
    raise exception 'Niet ingelogd';
  end if;

  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    raise exception 'Alarm niet gevonden';
  end if;

  if v_uid = a.triggered_by then
    v_allowed := true;
  elsif not coalesce(a.test_mode, false) then
    select exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and (
          (c.requester_id = a.triggered_by and c.target_id = v_uid)
          or (c.target_id = a.triggered_by and c.requester_id = v_uid)
        )
    ) into v_allowed;
  end if;

  if not v_allowed then
    raise exception 'Niet toegestaan';
  end if;

  select full_name into v_name from public.profiles where id = a.triggered_by;
  select to_jsonb(mi) into m from public.medical_info mi where mi.user_id = a.triggered_by;
  select to_jsonb(pi) into p from public.practical_info pi where pi.user_id = a.triggered_by;

  return jsonb_build_object(
    'alarm_id', a.id,
    'activator_id', a.triggered_by,
    'activator_name', coalesce(nullif(trim(v_name), ''), 'Iemand'),
    'medical', m,
    'practical', p
  );
end;
$$;

revoke all on function public.get_alarm_rescue_card(uuid) from public;
grant execute on function public.get_alarm_rescue_card(uuid) to authenticated;
