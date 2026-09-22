-- Contactenlijst: alfabetisch op naam (was: volgorde van toevoegen).
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
  order by lower(p.full_name) nulls last, lower(p.username);
$$;
