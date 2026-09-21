# NORI — notities voor toekomstige werksessies

## Direct deployen na elke wijziging (belangrijk, blijf dit doen)

Danny wil dat aanpassingen **meteen online** staan op
https://noodalarm.vercel.app — niet wachten tot hij zelf in Vercel
op Redeploy drukt.

**Actiepunt na ieder verzoek waarin code wordt aangepast:**

1. Commit + push naar de werkbranch.
2. Zorg dat de productie-deploy-branch (`claude/deploy-dit-vercel-fkoka1`
   of wat dan productie is) de wijziging bevat (merge/PR zoals gebruikelijk).
3. Deploy daarna meteen naar productie:

```bash
npx vercel deploy --prod --yes --token "$VERCEL_TOKEN"
```

(Als `VERCEL_ORG_ID` / `VERCEL_PROJECT_ID` gezet zijn: die meenemen via
`.vercel/project.json` of env, zodat het juiste project geraakt wordt.)

4. Controleer kort dat https://noodalarm.vercel.app de nieuwe code
   serveert (bijv. een unieke string uit de diff is zichtbaar).

Zonder `VERCEL_TOKEN` lukt alleen een anonieme tijdelijke URL — dat telt
**niet** als live. Vraag/herinner dan om het token; blokkeer het werk
niet, maar meld duidelijk dat productie nog niet is bijgewerkt.

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
- Bron van de edge function staat in `supabase/functions/post-update-digest/`.
  Secrets: `DIGEST_GROUP_ID`, `DIGEST_SENDER_ID` (+ service role). Het
  bericht **moet** een niet-lege `body` hebben (`alarm_messages_body_check`).

**Actiepunt voor mij (Claude), bij elke sessie waarin ik een
gebruikers-zichtbare verbetering aan NORI uitlever**: voeg er zelf een
rij aan `release_notes` voor toe (via `mcp__Supabase__execute_sql` /
`apply_migration`, insert in `public.release_notes(message_nl)`), in de
hierboven beschreven stijl. Niet vragen of het mag — dit is al
afgesproken staand beleid. Alleen weglaten wat puur technisch/intern is.
