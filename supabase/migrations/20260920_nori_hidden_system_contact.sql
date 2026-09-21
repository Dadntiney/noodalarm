-- NORI als vast systeemcontact / system-sender.
-- Geen gewone connection: niet zichtbaar in Contacten, niet uitnodigbaar,
-- niet verwijderbaar. Wel afzender van update-berichten in elke kring.

alter table public.profiles
  add column if not exists is_system boolean not null default false;

comment on column public.profiles.is_system is
  'Vast systeemprofiel (bijv. NORI). Geen gewoon contact; alleen system-sender.';

-- NORI markeren + officiële logo-avatar (zelfde asset als de app-icon).
update public.profiles
set
  is_system = true,
  first_name = 'NORI',
  last_name = E'\u200b',
  avatar_url = coalesce(
    nullif(trim(avatar_url), ''),
    'https://noodalarm.vercel.app/icon-192.png'
  )
where username = 'nori';

create or replace function public.nori_system_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.profiles where username = 'nori' and is_system limit 1;
$$;

revoke all on function public.nori_system_user_id() from public;
grant execute on function public.nori_system_user_id() to anon, authenticated;

create or replace function public.is_nori_system_user(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = p_user_id and is_system and username = 'nori'
  );
$$;

revoke all on function public.is_nori_system_user(uuid) from public;
grant execute on function public.is_nori_system_user(uuid) to anon, authenticated;

-- Profiel van systeemaccounts mag iedereen (ingelogd) lezen voor naam/avatar
-- in chat; gewone users blijven achter de bestaande connection-RLS.
drop policy if exists profiles_select_system on public.profiles;
create policy profiles_select_system on public.profiles
  for select
  to authenticated
  using (is_system = true);

-- Zoeken: systeemaccounts nooit in resultaten.
create or replace function public.search_users(p_query text)
returns table(
  id uuid,
  full_name text,
  username text,
  avatar_url text,
  connection_status text,
  connection_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.username, p.avatar_url,
    coalesce(c.status::text, 'none') as connection_status,
    c.id as connection_id
  from public.profiles p
  left join public.connections c
    on (c.requester_id = (select auth.uid()) and c.target_id = p.id)
    or (c.target_id = (select auth.uid()) and c.requester_id = p.id)
  where p.id <> (select auth.uid())
    and coalesce(p.is_system, false) = false
    and length(trim(p_query)) >= 2
    and (
      p.full_name ilike '%' || trim(p_query) || '%'
      or p.username ilike '%' || trim(p_query) || '%'
    )
  order by p.full_name
  limit 20;
$$;

-- Contactverzoek naar NORI / systeemaccounts blokkeren.
create or replace function public.send_connection_request(p_target_id uuid)
returns connections
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.connections;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_target_id = auth.uid() then raise exception 'Je kunt jezelf niet toevoegen'; end if;
  if not exists (select 1 from public.profiles where id = p_target_id and coalesce(is_system, false) = false) then
    raise exception 'Gebruiker niet gevonden';
  end if;

  select * into v_row from public.connections
    where (requester_id = auth.uid() and target_id = p_target_id)
       or (requester_id = p_target_id and target_id = auth.uid());

  if v_row.id is not null then
    if v_row.status in ('rejected','removed') then
      update public.connections
        set status = 'pending', requester_id = auth.uid(), target_id = p_target_id, updated_at = now()
        where id = v_row.id
        returning * into v_row;
    end if;
    return v_row;
  end if;

  insert into public.connections (requester_id, target_id, status)
  values (auth.uid(), p_target_id, 'pending')
  returning * into v_row;
  return v_row;
end;
$$;

-- Invite-link naar NORI werkt niet (geen gewoon contact).
create or replace function public.get_invite_profile(p_user_id uuid)
returns table(id uuid, full_name text, avatar_url text, username text)
language sql
security definer
set search_path = public
as $$
  select id, full_name, avatar_url, username
  from public.profiles
  where id = p_user_id
    and coalesce(is_system, false) = false;
$$;

-- Contactenlijst: systeemaccounts nooit tonen (ook als er ooit een rij zou bestaan).
create or replace function public.my_contacts()
returns table(
  connection_id uuid,
  contact_id uuid,
  full_name text,
  username text,
  avatar_url text,
  created_at timestamp with time zone
)
language sql
stable
set search_path = public
as $$
  select c.id,
    case when c.requester_id = (select auth.uid()) then c.target_id else c.requester_id end,
    p.full_name, p.username, p.avatar_url, c.created_at
  from public.connections c
  join public.profiles p on p.id = case
    when c.requester_id = (select auth.uid()) then c.target_id
    else c.requester_id
  end
  where (c.requester_id = (select auth.uid()) or c.target_id = (select auth.uid()))
    and c.status = 'accepted'
    and coalesce(p.is_system, false) = false
  order by c.created_at asc;
$$;

-- Facepile / groepsleden: geen systeemaccounts.
create or replace function public.get_group_participants(p_group_id uuid)
returns table(
  user_id uuid,
  full_name text,
  avatar_url text,
  phone_number text,
  added_at timestamp with time zone
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.avatar_url, p.phone_number, m.added_at
  from public.alarm_group_members m
  join public.profiles p on p.id = m.user_id
  where m.group_id = p_group_id
    and public.is_member_of_group(p_group_id)
    and coalesce(p.is_system, false) = false;
$$;

-- Digest blijft van NORI; lookup via helper i.p.v. hardcoded alleen.
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
  nori_id := public.nori_system_user_id();
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

  -- Één bericht per gebruikerskring (elke alarm_group). Leden van die kring
  -- zien het in Berichten; de client toont NORI-berichten uit je eigen groep.
  insert into public.alarm_messages (group_id, sender_id, body)
  select g.id, nori_id, body
  from public.alarm_groups g
  join public.profiles p on p.id = g.owner_id
  where coalesce(p.is_system, false) = false;

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

-- Bestaande losse connections met NORI opruimen (zonder membership-side-effects
-- nodig: die zouden via triggers lopen bij status-update; hard delete is ok
-- omdat NORI geen gewoon contact mag zijn).
delete from public.connections c
using public.profiles p
where p.is_system
  and (c.requester_id = p.id or c.target_id = p.id);

-- NORI hoort niet als lid in gebruikerskringen te staan.
delete from public.alarm_group_members m
using public.profiles p, public.alarm_groups g
where m.user_id = p.id
  and p.is_system
  and m.group_id = g.id
  and g.owner_id <> p.id;
