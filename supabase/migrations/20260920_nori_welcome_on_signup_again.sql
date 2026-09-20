-- Welkomstbericht weer bij succesvolle aanmelding (niet pas bij eerste contact).
-- Reden: je wordt welkom geheten bij NORI zelf; dat moment is de registratie.

create or replace function public.create_personal_alarm_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
  v_nori uuid;
begin
  insert into public.alarm_groups (owner_id) values (new.id);
  insert into public.alarm_group_members (group_id, user_id)
    select id, new.id from public.alarm_groups where owner_id = new.id;

  if coalesce(new.is_system, false) then
    return new;
  end if;

  if new.welcome_sent_at is not null then
    return new;
  end if;

  select id into v_group from public.alarm_groups where owner_id = new.id;
  if v_group is null then
    return new;
  end if;

  v_nori := public.nori_system_user_id();
  if v_nori is null then
    return new;
  end if;

  if exists (
    select 1 from public.alarm_messages m
    where m.group_id = v_group
      and m.sender_id = v_nori
      and m.body = public.nori_welcome_message_body()
  ) then
    update public.profiles
    set welcome_sent_at = coalesce(welcome_sent_at, now())
    where id = new.id;
    return new;
  end if;

  insert into public.alarm_messages (group_id, sender_id, body)
  values (v_group, v_nori, public.nori_welcome_message_body());

  update public.profiles
  set welcome_sent_at = now()
  where id = new.id
    and welcome_sent_at is null;

  return new;
end;
$$;

-- Connection-accept stuurt geen welkom meer (dat gebeurt bij signup).
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

  return new;
end;
$$;
