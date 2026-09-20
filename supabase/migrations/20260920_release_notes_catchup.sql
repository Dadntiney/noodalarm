-- Catch-up release notes voor gebruikers-zichtbare verbeteringen die vandaag
-- al live gingen, maar nog niet in public.release_notes stonden.
-- Alleen warme, niet-technische taal (zie CLAUDE.md).
--
-- Toepassen via Supabase SQL editor / mcp execute_sql. Daarna opnieuw
-- deployen van edge function post-update-digest (bron in
-- supabase/functions/post-update-digest/) zodat de dagelijkse digest
-- niet meer faalt op alarm_messages_body_check.

insert into public.release_notes (message_nl)
select m from (values
  ('Je ziet nu een duidelijk overzicht van je gesprekken. Tik op "Berichten" om te kiezen tussen jouw eigen kring en die van een contact.'),
  ('In de kring van iemand anders kun je meekijken, maar alleen typen als er een alarm loopt — zo blijft een bericht altijd bij de juiste mensen.'),
  ('Spraakberichten en foto''s maken met de camera werken nu soepeler, en foto''s openen schermvullend met een veeg om te sluiten.'),
  ('Bij medische informatie kun je nu ook je gewicht invullen, zodat hulpverleners dat meteen zien bij een alarm.'),
  ('Als iemand jouw contactverzoek weigert, zie je dat nu duidelijk terug — en de ander krijgt daar ook een melding van.')
) as v(m)
where not exists (
  select 1 from public.release_notes r where r.message_nl = v.m
);

-- UX-polish op de gesprekkenlijst (deze sessie)
insert into public.release_notes (message_nl)
select m from (values
  ('In de gesprekkenlijst zie je nu per contact of je alleen mag meelezen. De terug-knop brengt je weer naar het overzicht, en de titel toont van wie de kring is.')
) as v(m)
where not exists (
  select 1 from public.release_notes r where r.message_nl = v.m
);
