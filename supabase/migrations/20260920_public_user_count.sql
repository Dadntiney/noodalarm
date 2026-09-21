-- Publiek leesbaar totaal aantal NORI-gebruikers (alleen het getal).
-- SECURITY DEFINER zodat RLS op profiles de telling niet blokkeert;
-- geeft géén namen/gegevens prijs alleen count(*).

create or replace function public.public_user_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint from public.profiles;
$$;

comment on function public.public_user_count() is
  'Totaal aantal NORI-profielen; veilig voor client (alleen een getal).';

revoke all on function public.public_user_count() from public;
grant execute on function public.public_user_count() to anon, authenticated;

-- Optioneel: release note (idempotent)
insert into public.release_notes (message_nl)
select 'Onderaan bij Contacten zie je nu hoeveel mensen NORI veilig en met plezier gebruiken — een klein warm zinnetje met het echte aantal.'
where not exists (
  select 1 from public.release_notes r
  where r.message_nl = 'Onderaan bij Contacten zie je nu hoeveel mensen NORI veilig en met plezier gebruiken — een klein warm zinnetje met het echte aantal.'
);
