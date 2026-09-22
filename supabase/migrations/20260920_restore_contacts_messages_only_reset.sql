-- Herstel: contacten terugzetten na per ongeluk wissen, daarna ALLEEN
-- chatberichten leegmaken en één NORI-update plaatsen.
-- NOOIT opnieuw connections of alarm_group_members wissen voor een chat-reset.

-- Live uitgevoerd op 2026-09-20 via Management API (documentatie van de fix):
--
-- 1) connections hersteld (accepted):
--    dantiney ↔ sandrax
--    dantiney ↔ wally
--    maria ↔ paultje
-- 2) alarm_group_members weer bidirectioneel gezet (handle_connection_accepted-logica)
-- 3) delete from message_receipts; delete from alarm_messages;
-- 4) insert alarm_messages vanuit profiles.username = 'nori' in elke alarm_group

-- Idempotente guard: dit bestand is historisch; niet opnieuw blind uitvoeren
-- als de contacten al kloppen. Chat-reset (messages only) mag wel opnieuw:

delete from public.message_receipts;
delete from public.alarm_messages;

with nori as (
  select id from public.profiles where username = 'nori' limit 1
),
body as (
  select $msg$🆕 Update van NORI

Berichten is nu één eenvoudige groepschat met je contacten. Hier zie je de nieuwste verbeteringen van NORI — altijd van ons, nooit als bericht van iemand anders.$msg$::text as text
)
insert into public.alarm_messages (group_id, sender_id, body)
select g.id, n.id, left(b.text, 1000)
from public.alarm_groups g
cross join nori n
cross join body b
where n.id is not null
  and not exists (select 1 from public.alarm_messages);
