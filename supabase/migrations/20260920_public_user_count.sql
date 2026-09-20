-- Publiek leesbaar totaal aantal NORI-gebruikers (alleen het getal).
-- SECURITY DEFINER zodat RLS op profiles de telling niet blokkeert;
-- geeft géén namen/gegevens — alleen count(*). Systeemaccount @nori telt niet mee.

create or replace function public.public_user_count()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::bigint from public.profiles where username <> 'nori';
$$;

comment on function public.public_user_count() is
  'Totaal aantal NORI-gebruikers (zonder systeemaccount); veilig voor client (alleen een getal).';

revoke all on function public.public_user_count() from public;
grant execute on function public.public_user_count() to anon, authenticated;
