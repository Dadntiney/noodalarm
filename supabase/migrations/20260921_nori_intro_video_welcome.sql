-- NORI-uitlegvideo in de welkomstchat.
-- Nieuw bericht (apart van het welkomstbericht) met stabiele content-id
-- `nori-intro-video:v1`, zodat het precies één keer per gebruiker/groep
-- verschijnt — ook bij herlogin, refresh of opnieuw openen van Berichten.
--
-- Nieuwe accounts: create_personal_alarm_group plaatst welkom + video.
-- Bestaande accounts: eenmalige backfill hieronder.

alter table public.profiles
  add column if not exists welcome_video_sent_at timestamptz;

comment on column public.profiles.welcome_video_sent_at is
  'Tijdstip waarop het eenmalige NORI-uitlegvideo-bericht is geplaatst; null = nog niet.';

create or replace function public.nori_welcome_message_body()
returns text
language sql
immutable
as $$
  select $msg$👋 Welkom bij NORI!

Vanaf vandaag ben je verbonden met de mensen die jij vertrouwt. NORI helpt je om hen snel te bereiken wanneer dat nodig is.

Welkom bij NORI!$msg$::text;
$$;

create or replace function public.nori_intro_video_message_body()
returns text
language sql
immutable
as $$
  -- Marker `nori-intro-video:v1` is de stabiele content-id (frontend
  -- toont de video en verbergt de marker). Tekst mag wijzigen zolang
  -- de marker gelijk blijft — dan blijft de unique index werken.
  select $msg$Bekijk deze korte video en ontdek hoe NORI werkt.

nori-intro-video:v1$msg$::text;
$$;

revoke all on function public.nori_intro_video_message_body() from public;

-- Max. één uitlegvideo-bericht van NORI per groep (content-id v1).
create unique index if not exists alarm_messages_one_nori_intro_video_v1_per_group
  on public.alarm_messages (group_id)
  where sender_id = '961b3add-ad24-4e56-8c43-461676800cb2'
    and body like '%nori-intro-video:v1%';

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

  select id into v_group from public.alarm_groups where owner_id = new.id;
  if v_group is null then
    return new;
  end if;

  v_nori := public.nori_system_user_id();
  if v_nori is null then
    return new;
  end if;

  -- Welkomstbericht (eenmalig).
  if new.welcome_sent_at is null then
    if exists (
      select 1 from public.alarm_messages m
      where m.group_id = v_group
        and m.sender_id = v_nori
        and m.body = public.nori_welcome_message_body()
    ) then
      update public.profiles
      set welcome_sent_at = coalesce(welcome_sent_at, now())
      where id = new.id;
    else
      insert into public.alarm_messages (group_id, sender_id, body)
      values (v_group, v_nori, public.nori_welcome_message_body());
      update public.profiles
      set welcome_sent_at = now()
      where id = new.id
        and welcome_sent_at is null;
    end if;
  end if;

  -- Uitlegvideo (eenmalig, aparte rij — blijft staan om opnieuw te bekijken).
  if new.welcome_video_sent_at is null then
    if exists (
      select 1 from public.alarm_messages m
      where m.group_id = v_group
        and m.sender_id = v_nori
        and m.body like '%nori-intro-video:v1%'
    ) then
      update public.profiles
      set welcome_video_sent_at = coalesce(welcome_video_sent_at, now())
      where id = new.id;
    else
      insert into public.alarm_messages (group_id, sender_id, body)
      values (v_group, v_nori, public.nori_intro_video_message_body());
      update public.profiles
      set welcome_video_sent_at = now()
      where id = new.id
        and welcome_video_sent_at is null;
    end if;
  end if;

  return new;
end;
$$;

-- Eenmalige backfill voor bestaande gebruikers (idempotent).
do $$
declare
  v_nori uuid := public.nori_system_user_id();
  r record;
begin
  if v_nori is null then
    return;
  end if;

  for r in
    select g.id as group_id, g.owner_id
    from public.alarm_groups g
    join public.profiles p on p.id = g.owner_id
    where coalesce(p.is_system, false) = false
      and p.welcome_video_sent_at is null
      and not exists (
        select 1 from public.alarm_messages m
        where m.group_id = g.id
          and m.sender_id = v_nori
          and m.body like '%nori-intro-video:v1%'
      )
  loop
    begin
      insert into public.alarm_messages (group_id, sender_id, body)
      values (r.group_id, v_nori, public.nori_intro_video_message_body());
    exception when unique_violation then
      null;
    end;

    update public.profiles
    set welcome_video_sent_at = coalesce(welcome_video_sent_at, now())
    where id = r.owner_id;
  end loop;

  -- Groepen die het bericht al hebben (race / eerdere poging): flag zetten.
  update public.profiles p
  set welcome_video_sent_at = coalesce(welcome_video_sent_at, now())
  where p.welcome_video_sent_at is null
    and exists (
      select 1
      from public.alarm_groups g
      join public.alarm_messages m on m.group_id = g.id
      where g.owner_id = p.id
        and m.sender_id = v_nori
        and m.body like '%nori-intro-video:v1%'
    );
end $$;

-- Gebruikersvriendelijke release note (digest postt voorlopig niet in chat,
-- maar de note blijft staan voor wanneer digests weer aan gaan).
insert into public.release_notes (message_nl)
select 'NORI heeft nu een korte uitlegvideo in je welkomstchat. Tik op afspelen om rustig te zien hoe NORI werkt — Contacten, Berichten en de ALARM-knop.'
where not exists (
  select 1 from public.release_notes
  where message_nl like 'NORI heeft nu een korte uitlegvideo%'
);

-- Idempotente RPC: frontend mag dit veilig aanroepen na login.
-- Plaatst het uitlegvideo-bericht hoogstens één keer in de eigen groep.
create or replace function public.ensure_my_nori_intro_video()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_group uuid;
  v_nori uuid;
begin
  if v_uid is null then
    return false;
  end if;

  if exists (
    select 1 from public.profiles
    where id = v_uid and welcome_video_sent_at is not null
  ) then
    return false;
  end if;

  select id into v_group from public.alarm_groups where owner_id = v_uid;
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
      and m.body like '%nori-intro-video:v1%'
  ) then
    update public.profiles
    set welcome_video_sent_at = coalesce(welcome_video_sent_at, now())
    where id = v_uid;
    return false;
  end if;

  begin
    insert into public.alarm_messages (group_id, sender_id, body)
    values (v_group, v_nori, public.nori_intro_video_message_body());
  exception when unique_violation then
    null;
  end;

  update public.profiles
  set welcome_video_sent_at = now()
  where id = v_uid
    and welcome_video_sent_at is null;

  return true;
end;
$$;

revoke all on function public.ensure_my_nori_intro_video() from public;
grant execute on function public.ensure_my_nori_intro_video() to authenticated;
