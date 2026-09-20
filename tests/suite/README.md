# NORI load / E2E suite

Synthetische gebruikers die elkaar uitnodigen, test-alarmen sturen, chatten en weer opgeruimd worden.

## Waarom

Handmatig testen met 1–2 accounts mist race conditions en FK-problemen. Deze suite oefent de echte edge functions + RPCs, zonder 1000 browser-bots (duur, rate-limits, rommel).

## Vereisten

- Node 18+
- `SUPABASE_ACCESS_TOKEN` in `/workspace/.env.local` (Management API → cleanup)
- Anon key: uit `noodalarm.html` of `SUPABASE_ANON_KEY`

## Gebruik

```bash
cd tests/suite
node run.mjs                 # 6 users (aanbevolen smoke)
node run.mjs --users=20      # medium
node run.mjs --users=8 --dense
node run.mjs --cleanup-only  # alle lt*-users weg
node run.mjs --keep          # users laten staan (debug)
```

## Wat er gebeurt

1. `register` → N users (`lt{run}{nnn}@gmail.com`)
2. Login round-trip
3. Ring-connecties (of `--dense`: iedereen↔iedereen)
4. Medische + praktische info upsert
5. Chatbericht in eigen groep
6. `send-alert` met **testMode: true** (geen echte push/mail-stress)
7. Alarmen beëindigen
8. SQL-cleanup in FK-volgorde

## Grenzen (productie)

| | Advies |
|---|---|
| Users per run | ≤ 20 (max hard 50) |
| Dense | alleen ≤ 12 |
| Echte alarms | suite gebruikt alleen testMode |
| 1000 users | **niet** op productie — aparte staging |

## Opruimen

Alle suite-users hebben username-prefix `lt`. Bij crash:

```bash
node run.mjs --cleanup-only
```
