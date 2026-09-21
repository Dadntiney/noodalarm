-- Bij een écht noodalarm plaatst NORI één chatbericht in de kring van de
-- activator met locatie + medische reddingsinfo. Helpers lezen dat in de
-- chat i.p.v. grote kaarten die het typen blokkeren.
-- test_mode: geen bericht (contacten merken niets).

create or replace function public.nori_alarm_rescue_message_body(p_alarm_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a record;
  p record;
  m record;
  prac record;
  v_name text;
  v_lines text[] := array[]::text[];
  v_body text;
  v_maps text;
  v_line text;
begin
  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    return null;
  end if;

  select full_name into v_name from public.profiles where id = a.triggered_by;
  v_name := coalesce(nullif(trim(v_name), ''), 'Iemand');

  v_lines := array_append(v_lines, '🚨 Alarm van ' || v_name);
  v_lines := array_append(v_lines, '');
  v_lines := array_append(v_lines, 'NORI deelt nu locatie en medische info, zodat jullie meteen kunnen helpen.');

  if a.lat is not null and a.lng is not null then
    v_maps := 'https://www.google.com/maps/search/?api=1&query=' || a.lat::text || ',' || a.lng::text;
    v_lines := array_append(v_lines, '');
    v_lines := array_append(v_lines, '📍 Locatie');
    v_lines := array_append(v_lines, v_maps);
    if a.location_accuracy is not null then
      v_lines := array_append(v_lines, '±' || round(a.location_accuracy)::text || ' m nauwkeurig');
    end if;
  end if;

  select * into m from public.medical_info where user_id = a.triggered_by;
  select * into prac from public.practical_info where user_id = a.triggered_by;

  if m.user_id is not null or (prac.user_id is not null and prac.spare_key_location is not null) then
    v_lines := array_append(v_lines, '');
    v_lines := array_append(v_lines, '🩺 Reddingskaart');

    if m.user_id is not null and m.resuscitate is not null then
      if m.resuscitate then
        v_lines := array_append(v_lines, '✅ Mag gereanimeerd worden');
      else
        v_lines := array_append(v_lines, '⛔ Wil NIET gereanimeerd worden');
      end if;
    end if;

    if prac.spare_key_location is not null and length(trim(prac.spare_key_location)) > 0 then
      v_lines := array_append(v_lines, '🔑 Sleutel: ' || trim(prac.spare_key_location));
    end if;
    if m.advance_directive is not null and length(trim(m.advance_directive)) > 0 then
      v_lines := array_append(v_lines, 'Speciale wensen: ' || trim(m.advance_directive));
    end if;
    if coalesce(m.pacemaker_icd, false) then
      v_lines := array_append(v_lines, '⚠️ Pacemaker/ICD');
    end if;
    if coalesce(m.pregnant, false) then
      v_lines := array_append(v_lines, '⚠️ Zwanger');
    end if;
    if m.allergies is not null and length(trim(m.allergies)) > 0 then
      v_lines := array_append(v_lines, 'Allergieën: ' || trim(m.allergies));
    end if;
    if m.medications is not null and length(trim(m.medications)) > 0 then
      v_lines := array_append(v_lines, 'Medicijnen: ' || trim(m.medications));
    end if;
    if m.conditions is not null and length(trim(m.conditions)) > 0 then
      v_lines := array_append(v_lines, 'Aandoeningen: ' || trim(m.conditions));
    end if;
    if m.birth_date is not null then
      v_lines := array_append(v_lines, 'Geboren: ' || to_char(m.birth_date, 'DD-MM-YYYY'));
    end if;
    if m.weight_kg is not null then
      v_lines := array_append(v_lines, 'Gewicht: ' || m.weight_kg::text || ' kg');
    end if;
    if m.mobility is not null then
      v_line := case m.mobility
        when 'good' then 'Goed ter been'
        when 'walker' then 'Loophulpmiddel'
        when 'wheelchair' then 'Rolstoel'
        else m.mobility
      end;
      v_lines := array_append(v_lines, 'Mobiliteit: ' || v_line);
    end if;
    if m.contact1_name is not null and length(trim(m.contact1_name)) > 0 then
      v_lines := array_append(v_lines, 'Contact 1: ' || trim(m.contact1_name)
        || coalesce(' — ' || nullif(trim(m.contact1_relation), ''), '')
        || coalesce(' · ' || nullif(trim(m.contact1_phone), ''), ''));
    end if;
    if m.contact2_name is not null and length(trim(m.contact2_name)) > 0 then
      v_lines := array_append(v_lines, 'Contact 2: ' || trim(m.contact2_name)
        || coalesce(' — ' || nullif(trim(m.contact2_relation), ''), '')
        || coalesce(' · ' || nullif(trim(m.contact2_phone), ''), ''));
    end if;
    if (m.doctor_name is not null and length(trim(m.doctor_name)) > 0)
       or (m.doctor_phone is not null and length(trim(m.doctor_phone)) > 0) then
      v_lines := array_append(v_lines, 'Huisarts: '
        || coalesce(nullif(trim(m.doctor_name), ''), '')
        || case when m.doctor_name is not null and m.doctor_phone is not null then ' — ' else '' end
        || coalesce(nullif(trim(m.doctor_phone), ''), ''));
    end if;
    if m.hospital is not null and length(trim(m.hospital)) > 0 then
      v_lines := array_append(v_lines, 'Ziekenhuis: ' || trim(m.hospital));
    end if;
    if m.notes is not null and length(trim(m.notes)) > 0 then
      v_lines := array_append(v_lines, 'Overig: ' || trim(m.notes));
    end if;
  else
    v_lines := array_append(v_lines, '');
    v_lines := array_append(v_lines, '🩺 Nog geen medische info ingevuld.');
  end if;

  v_lines := array_append(v_lines, '');
  v_lines := array_append(v_lines, '📞 Bel 112 bij nood.');

  v_body := array_to_string(v_lines, E'\n');
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
begin
  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    raise exception 'Alarm niet gevonden';
  end if;

  -- Alleen de activator (of service role) mag dit posten.
  if auth.uid() is not null and auth.uid() <> a.triggered_by then
    raise exception 'Niet toegestaan';
  end if;

  -- Oefenalarm: stil — geen chatbericht dat contacten kunnen zien.
  if coalesce(a.test_mode, false) then
    return null;
  end if;

  -- Idempotent: één reddingsbericht per alarm.
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
  returning id into v_msg_id;

  return v_msg_id;
end;
$$;

revoke all on function public.post_nori_alarm_rescue_message(uuid) from public;
grant execute on function public.post_nori_alarm_rescue_message(uuid) to authenticated;
