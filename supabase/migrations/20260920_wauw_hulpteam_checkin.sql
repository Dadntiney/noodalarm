-- Wauw-features: hulpteam (omw), check-in voorkeur
-- 1) Onderscheid "gezien" vs "ik kom eraan" op alarm-notificaties
alter table public.notifications
  add column if not exists omw_at timestamptz;

-- 2) Hulpteam-status: elke groepsgenoot mag zien wie reageert / komt
drop function if exists public.get_alarm_acknowledgments(uuid);
create function public.get_alarm_acknowledgments(p_alarm_id uuid)
returns table(user_id uuid, is_read boolean, omw_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  select a.group_id into v_group_id from public.alarms a where a.id = p_alarm_id;
  if v_group_id is null then
    return;
  end if;
  if not public.is_member_of_group(v_group_id) then
    return;
  end if;
  return query
    select n.user_id, n.is_read, n.omw_at
    from public.notifications n
    where n.related_alarm_id = p_alarm_id and n.type = 'alarm';
end;
$$;

-- 3) Optionele check-in (standaard uit) — voorkeur op profiel
alter table public.profiles
  add column if not exists check_in_enabled boolean not null default false;

alter table public.profiles
  add column if not exists check_in_at timestamptz;

comment on column public.profiles.check_in_enabled is
  'Als true: NORI mag periodiek vragen of je er nog bent; bij stilte worden noodcontacten vriendelijk geïnformeerd.';
comment on column public.profiles.check_in_at is
  'Laatste keer dat de gebruiker zelf bevestigde “ik ben ok”.';

grant execute on function public.get_alarm_acknowledgments(uuid) to authenticated;

-- Zachte tip aan noodcontacten als check-in >35 dagen stil is (later via cron).
create or replace function public.run_check_in_watch()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  contact record;
  n int := 0;
begin
  for r in
    select p.id, p.full_name, p.check_in_at
    from public.profiles p
    where p.check_in_enabled = true
      and coalesce(p.is_system, false) = false
      and (p.check_in_at is null or p.check_in_at < now() - interval '35 days')
  loop
    for contact in
      select case when c.requester_id = r.id then c.target_id else c.requester_id end as uid
      from public.connections c
      where c.status = 'accepted'
        and (c.requester_id = r.id or c.target_id = r.id)
    loop
      insert into public.notifications (user_id, type, title, message, is_read)
      values (
        contact.uid,
        'check_in',
        'Even checken',
        coalesce(r.full_name, 'Iemand in je kring') || ' heeft een tijdje niet laten weten dat alles goed is. Misschien even langskomen of bellen? Dit is geen alarm.',
        false
      );
      n := n + 1;
    end loop;
  end loop;
  return n;
end;
$$;
