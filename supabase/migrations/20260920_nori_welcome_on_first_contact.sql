-- Welkomstbericht van NORI bij het ÉERSTE geaccepteerde contact,
-- niet meer bij kale aanmelding (toen was "jullie samen" nog leeg).

-- 1) Signup-trigger terug naar alleen groep aanmaken.
create or replace function public.create_personal_alarm_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.alarm_groups (owner_id) values (new.id);
  insert into public.alarm_group_members (group_id, user_id)
    select id, new.id from public.alarm_groups where owner_id = new.id;
  return new;
end;
$$;

-- 2) Helper: stuur welkom als dit iemands eerste accepted contact is.
create or replace function public.send_nori_welcome_if_first_contact(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
  v_nori uuid;
  v_other_accepted int;
begin
  if p_user_id is null then
    return false;
  end if;

  -- Systeem / al welkom gehad → stop.
  if exists (
    select 1 from public.profiles
    where id = p_user_id
      and (coalesce(is_system, false) = true or welcome_sent_at is not null)
  ) then
    return false;
  end if;

  -- Andere accepted connections naast de zojuist geaccepteerde?
  -- (Deze functie draait NÁ status=accepted, dus count >= 1.
  --  First contact ⇔ precies 1 accepted connection.)
  select count(*)::int into v_other_accepted
  from public.connections c
  where c.status = 'accepted'
    and (c.requester_id = p_user_id or c.target_id = p_user_id);

  if coalesce(v_other_accepted, 0) <> 1 then
    return false;
  end if;

  select id into v_group from public.alarm_groups where owner_id = p_user_id;
  if v_group is null then
    return false;
  end if;

  v_nori := public.nori_system_user_id();
  if v_nori is null then
    return false;
  end if;

  if exists (
    select 1 from public.alarm_messages m
    where m.group_id = v_group
      and m.sender_id = v_nori
      and m.body = public.nori_welcome_message_body()
  ) then
    update public.profiles
    set welcome_sent_at = coalesce(welcome_sent_at, now())
    where id = p_user_id;
    return false;
  end if;

  insert into public.alarm_messages (group_id, sender_id, body)
  values (v_group, v_nori, public.nori_welcome_message_body());

  update public.profiles
  set welcome_sent_at = now()
  where id = p_user_id
    and welcome_sent_at is null;

  return true;
end;
$$;

revoke all on function public.send_nori_welcome_if_first_contact(uuid) from public;

-- 3) Bij accept: voor beide partijen checken.
create or replace function public.handle_connection_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_requester_group uuid;
  v_target_group uuid;
  v_target_name text;
  v_requester_language text;
begin
  if new.status <> 'accepted' or old.status = 'accepted' then
    return new;
  end if;

  select id into v_requester_group from public.alarm_groups where owner_id = new.requester_id;
  select id into v_target_group from public.alarm_groups where owner_id = new.target_id;

  insert into public.alarm_group_members (group_id, user_id) values (v_requester_group, new.target_id)
    on conflict do nothing;
  insert into public.alarm_group_members (group_id, user_id) values (v_target_group, new.requester_id)
    on conflict do nothing;

  select full_name into v_target_name from public.profiles where id = new.target_id;
  select language into v_requester_language from public.profiles where id = new.requester_id;

  insert into public.notifications (user_id, type, title, message, related_connection_id)
  values (
    new.requester_id,
    'connection_accepted',
    case when v_requester_language = 'en' then 'Contact request accepted' else 'Contactverzoek geaccepteerd' end,
    case when v_requester_language = 'en'
      then coalesce(v_target_name, 'Someone') || ' has accepted your contact request.'
      else coalesce(v_target_name, 'Iemand') || ' heeft je contactverzoek geaccepteerd.'
    end,
    new.id
  );

  -- Welkom van NORI op het moment dat je niet meer alleen bent.
  perform public.send_nori_welcome_if_first_contact(new.requester_id);
  perform public.send_nori_welcome_if_first_contact(new.target_id);

  return new;
end;
$$;

-- 4) Bestaande users die al contacten hebben: markeer als "welkom gehad"
--    zonder bericht te sturen (voorkomt verrassing bij een nieuw contact).
update public.profiles p
set welcome_sent_at = now()
where p.welcome_sent_at is null
  and coalesce(p.is_system, false) = false
  and exists (
    select 1
    from public.connections c
    where c.status = 'accepted'
      and (c.requester_id = p.id or c.target_id = p.id)
  );
