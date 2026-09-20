# NORI — notities voor toekomstige werksessies

## NORI als verborgen systeemcontact / system-sender

NORI (`profiles.username = 'nori'`, `is_system = true`, id
`961b3add-ad24-4e56-8c43-461676800cb2`) is **geen gewoon contact**:

- Verschijnt niet in Contacten, zoeken, uitnodigen of facepile.
- Kan niet worden toegevoegd of verwijderd.
- Is wél de vaste afzender van update-berichten in Berichten (officieel
  logo + badge “Update”).
- Digests gaan via `public.run_update_digest()` naar elke gebruikers-
  `alarm_group` (niet naar NORI’s eigen groep). Cron job
  `nori-daily-update-digest` roept die Postgres-functie aan.
- Frontend toont NORI-berichten alleen uit de eigen groep van de
  gebruiker (`myGroupId`), zodat dezelfde update niet N keer
  verschijnt via andermans groepen.

Nooit een normale `connections`-rij voor NORI aanmaken (bidirectionele
membership-trigger maakt een rommel van de kringen).

### Welkomstbericht bij nieuwe aanmelding
`create_personal_alarm_group` plaatst **één** bericht van NORI in de nieuwe
kring, direct na registratie (`profiles.welcome_sent_at` + unique index).
Tekst: `public.nori_welcome_message_body()`. Badge in de UI: **Welkom**
(updates blijven **Update**). Nooit vanuit de frontend opnieuw aanmaken
bij login/refresh/nieuwe contacten.

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
- Cron `nori-daily-update-digest` (08:00 UTC) roept
  `select public.run_update_digest();` aan. Die bundelt rijen met
  `announced_at is null` tot één vriendelijk bericht van afzender NORI
  in elke gebruikerskring (alleen als er echt iets nieuws is).
- Edge function `post-update-digest` is legacy/fallback; bron in
  `supabase/functions/post-update-digest/`. Het bericht **moet** een
  niet-lege `body` hebben (`alarm_messages_body_check`, max 1000).

**Actiepunt voor mij (Claude), bij elke sessie waarin ik een
gebruikers-zichtbare verbetering aan NORI uitlever**: voeg er zelf een
rij aan `release_notes` voor toe (via Management API / SQL insert in
`public.release_notes(message_nl)`), in de hierboven beschreven stijl.
Niet vragen of het mag — dit is al afgesproken staand beleid. Alleen
weglaten wat puur technisch/intern is.
