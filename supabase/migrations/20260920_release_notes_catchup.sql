-- Catch-up release notes voor gebruikers-zichtbare verbeteringen.
-- Alleen warme, niet-technische taal (zie CLAUDE.md).
--
-- Toepassen via Supabase SQL editor / mcp execute_sql. Daarna opnieuw
-- deployen van edge function post-update-digest (bron in
-- supabase/functions/post-update-digest/) zodat de dagelijkse digest
-- niet meer faalt op alarm_messages_body_check.

insert into public.release_notes (message_nl)
select m from (values
  ('Berichten is nu één simpele groepschat met je contacten — geen losse gesprekken of privéberichten. Wat jij typt, zien al je bevestigde contacten.'),
  ('Spraakberichten en foto''s maken met de camera werken nu soepeler, en foto''s openen schermvullend met een veeg om te sluiten.'),
  ('Bij medische informatie kun je nu ook je gewicht invullen, zodat hulpverleners dat meteen zien bij een alarm.'),
  ('Als iemand jouw contactverzoek weigert, zie je dat nu duidelijk terug — en de ander krijgt daar ook een melding van.')
) as v(m)
where not exists (
  select 1 from public.release_notes r where r.message_nl = v.m
);
