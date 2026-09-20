-- Eenmalig: alle groepschats leegmaken en per groep alleen de laatste
-- NORI-update(s) als bericht bericht zetten. Daarna post post-update-digest
-- voortaan naar élke alarm_group (zie edge function-bron).

-- 1) Alles stil: receipts eerst (FK), daarna berichten.
delete from public.message_receipts;
delete from public.alarm_messages;

-- 2) Bouw één warme update-tekst uit openstaande release_notes,
--    anders de meest recente aangekondigde notities (max 5).
with pending as (
  select message_nl
  from public.release_notes
  where announced_at is null
    and coalesce(trim(message_nl), '') <> ''
  order by id asc
),
fallback as (
  select message_nl
  from public.release_notes
  where coalesce(trim(message_nl), '') <> ''
  order by id desc
  limit 5
),
picked as (
  select message_nl from pending
  union all
  select message_nl from fallback
  where not exists (select 1 from pending)
),
ordered as (
  select message_nl, row_number() over () as rn
  from picked
),
digest as (
  select case
    when count(*) = 0 then null
    when count(*) = 1 then '🆕 Update van NORI' || E'\n\n' || min(message_nl)
    else '🆕 Updates van NORI' || E'\n\n' || string_agg('• ' || message_nl, E'\n' order by rn)
  end as body
  from ordered
)
insert into public.alarm_messages (group_id, sender_id, body)
select g.id, g.owner_id, d.body
from public.alarm_groups g
cross join digest d
where d.body is not null
  and coalesce(trim(d.body), '') <> '';

-- 3) Openstaande notes als aangekondigd markeren (ze staan nu in elke chat).
update public.release_notes
set announced_at = now()
where announced_at is null;
