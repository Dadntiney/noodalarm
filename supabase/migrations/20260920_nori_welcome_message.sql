-- Eenmalig NORI-welkomstbericht bij succesvolle aanmelding.
-- Hangt aan create_personal_alarm_group (ná aanmaken van de kring),
-- zodat het bericht meteen als echte alarm_messages-rij bestaat.
-- Idempotent: profiles.welcome_sent_at + partial unique index.

alter table public.profiles
  add column if not exists welcome_sent_at timestamptz;

comment on column public.profiles.welcome_sent_at is
  'Tijdstip waarop het eenmalige NORI-welkomstbericht is geplaatst; null = nog niet.';

create or replace function public.nori_welcome_message_body()
returns text
language sql
immutable
as $$
  select $msg$👋 Welkom bij NORI!

Vanaf vandaag zijn jullie samen verbonden in deze groep. NORI is er om jullie te helpen, belangrijke updates te delen en ervoor te zorgen dat jullie op de hoogte blijven.

Ik wens jullie veel plezier met NORI en vooral veel fijne momenten samen. 💛

Welkom bij NORI!$msg$::text;
$$;

revoke all on function public.nori_welcome_message_body() from public;

create or replace function public.create_personal_alarm_group()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group uuid;
  v_nori uuid;
  v_body text;
begin
  insert into public.alarm_groups (owner_id) values (new.id);
  insert into public.alarm_group_members (group_id, user_id)
    select id, new.id from public.alarm_groups where owner_id = new.id;

  -- Systeemaccounts (NORI zelf) krijgen geen welkomstbericht.
  if coalesce(new.is_system, false) then
    return new;
  end if;

  -- Al verstuurd? Nooit opnieuw (herlogin / migratie / race).
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

  -- Extra guard: zelfde welkomsttekst mag niet dubbel in deze groep.
  if exists (
    select 1
    from public.alarm_messages m
    where m.group_id = v_group
      and m.sender_id = v_nori
      and m.body = public.nori_welcome_message_body()
  ) then
    update public.profiles
    set welcome_sent_at = coalesce(welcome_sent_at, now())
    where id = new.id;
    return new;
  end if;

  v_body := public.nori_welcome_message_body();

  insert into public.alarm_messages (group_id, sender_id, body)
  values (v_group, v_nori, v_body);

  update public.profiles
  set welcome_sent_at = now()
  where id = new.id
    and welcome_sent_at is null;

  return new;
end;
$$;

-- DB-niveau: max. één welkomstbericht van NORI per groep.
create unique index if not exists alarm_messages_one_nori_welcome_per_group
  on public.alarm_messages (group_id)
  where sender_id = '961b3add-ad24-4e56-8c43-461676800cb2'
    and body like E'👋 Welkom bij NORI!\n%';
