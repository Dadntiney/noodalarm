# NORI — notities voor toekomstige werksessies

## Dagelijkse update-melding (belangrijk, blijf dit doen)

Danny wil geen omkijken hebben naar het informeren van zijn noodcontacten
over app-updates. Daarom bestaat er een automatisch mechanisme:

- Tabel `public.release_notes` (Supabase project `vdohfnmhzbttqmsinoln`) met
  kolommen `message_nl` en `announced_at`.
- Elke rij is één update, geschreven in simpele, warme, **niet-technische**
  taal die ook iemand van 60+ meteen snapt — geen jargon, geen
  implementatiedetails, geen dingen die alleen intern/onder de motorkap
  relevant zijn (bugfixes zonder zichtbaar effect, beveiligingsfixes,
  performance-interne dingen). Alleen wat een gewone gebruiker echt merkt.
- Een Supabase Edge Function `post-update-digest`, dagelijks om 08:00 UTC
  getriggerd via `pg_cron`/`pg_net` (cron job `nori-daily-update-digest`),
  verzamelt alle rijen met `announced_at is null`, bundelt ze tot één
  vriendelijk bericht en post dat in Danny's groepschat (alleen als er
  ook echt iets nieuws is — geen bericht op stille dagen). Zet daarna
  `announced_at` op die rijen.

**Actiepunt voor mij (Claude), bij elke sessie waarin ik een
gebruikers-zichtbare verbetering aan NORI uitlever**: voeg er zelf een
rij aan `release_notes` voor toe (via `mcp__Supabase__execute_sql` /
`apply_migration`, insert in `public.release_notes(message_nl)`), in de
hierboven beschreven stijl. Niet vragen of het mag — dit is al
afgesproken staand beleid. Alleen weglaten wat puur technisch/intern is.
