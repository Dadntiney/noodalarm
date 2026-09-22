#!/usr/bin/env node
/**
 * NORI load/E2E suite
 *
 * Gebruik:
 *   node run.mjs                 # 6 users, ring-connecties
 *   node run.mjs --users=20      # grotere run
 *   node run.mjs --users=8 --dense
 *   node run.mjs --cleanup-only  # alle lt*-testusers weg
 *
 * Vereist: SUPABASE_ACCESS_TOKEN in .env.local (voor cleanup).
 * Anon key komt uit noodalarm.html (of env).
 *
 * Let op: dit raakt de PRODUCTIE-Supabase. Gebruik kleine aantallen.
 * Geen echte nood-alarms (alles testMode). Geen 1000 users — te duur/ruis.
 */

import { step, summary, ok } from './lib/assert.mjs';
import { config } from './lib/config.mjs';
import { createUsers, loginUser } from './lib/users.mjs';
import { wireConnections, myContacts } from './lib/connections.mjs';
import { triggerTestAlarm, endActiveAlarms } from './lib/alarms.mjs';
import { sendChatMessage } from './lib/chat.mjs';
import { upsertMedicalMerge, upsertPractical } from './lib/medical.mjs';
import { cleanupUserIds, cleanupByPrefix } from './lib/cleanup.mjs';

function parseArgs(argv) {
  const out = { users: 6, dense: false, cleanupOnly: false, keep: false, concurrency: 3 };
  for (const a of argv.slice(2)) {
    if (a === '--cleanup-only') out.cleanupOnly = true;
    else if (a === '--dense') out.dense = true;
    else if (a === '--keep') out.keep = true;
    else if (a.startsWith('--users=')) out.users = Math.max(2, Number(a.slice(8)) || 6);
    else if (a.startsWith('--concurrency=')) out.concurrency = Math.max(1, Number(a.slice(14)) || 3);
    else if (a === '--help' || a === '-h') out.help = true;
  }
  return out;
}

function printHelp() {
  console.log(`NORI suite

  node run.mjs [--users=N] [--dense] [--keep] [--concurrency=N]
  node run.mjs --cleanup-only

  --users=N       Aantal synthetische users (default 6, advies ≤20 op productie)
  --dense         Iedereen met iedereen verbinden (alleen klein N)
  --keep          Users niet opruimen na de run
  --cleanup-only  Alleen lt*-testusers verwijderen
  --concurrency=N Parallel registeren (default 3)
`);
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    printHelp();
    process.exit(0);
  }

  console.log('NORI suite');
  console.log(`  project: ${config.projectRef}`);
  console.log(`  prefix:  ${config.prefix}*`);
  if (!config.accessToken) {
    console.warn('  ⚠ Geen SUPABASE_ACCESS_TOKEN — cleanup zal falen');
  }

  if (args.cleanupOnly) {
    console.log('\n== Cleanup only ==');
    const result = await cleanupByPrefix(config.prefix);
    console.log(`  Verwijderd: ${result.deleted} users`, result.usernames?.slice(0, 20) || []);
    process.exit(0);
  }

  if (args.users > 50) {
    console.error('Max 50 users per run op productie. Gebruik staging voor groter.');
    process.exit(2);
  }
  if (args.dense && args.users > 12) {
    console.error('--dense met >12 users is te zwaar (O(n²) invites).');
    process.exit(2);
  }

  let userIds = [];
  let runId = '';

  try {
    console.log(`\n== 1. Users aanmaken (${args.users}) ==`);
    await step('register', async () => {
      const created = await createUsers(args.users, { concurrency: args.concurrency });
      runId = created.runId;
      userIds = created.users.map(u => u.id);
      globalThis.__suiteUsers = created.users;
      ok(created.users.length === args.users, 'Niet alle users aangemaakt');
    });
    const users = globalThis.__suiteUsers;

    console.log('\n== 2. Login round-trip ==');
    await step('login eerste user', async () => {
      const u = await loginUser(users[0]);
      users[0].token = u.token;
    });

    console.log(`\n== 3. Connecties (${args.dense ? 'dense' : 'ring'}) ==`);
    await step('invite + accept', async () => {
      await wireConnections(users, { dense: args.dense });
    });
    await step('my_contacts niet leeg', async () => {
      const contacts = await myContacts(users[0]);
      ok(contacts.length >= 1, 'User 0 heeft geen contacten', contacts);
    });

    console.log('\n== 4. Medisch / praktisch ==');
    await step('medical + practical upsert', async () => {
      await upsertMedicalMerge(users[0]);
      await upsertPractical(users[0]);
    });

    console.log('\n== 5. Chat ==');
    await step('bericht sturen', async () => {
      await sendChatMessage(users[0], `Suite ping ${runId}`);
    });

    console.log('\n== 6. Test-alarmen ==');
    await step('send-alert testMode', async () => {
      const result = await triggerTestAlarm(users[0]);
      ok(result.contactCount >= 1 || (result.notified && result.notified.length >= 0),
        'Alarm response incompleet', result);
    });
    await step('alarms beëindigen', async () => {
      await endActiveAlarms(users[0]);
    });

    // Extra: een paar users parallel test-alarm
    if (users.length >= 3) {
      await step('3 parallelle test-alarmen', async () => {
        await Promise.all(users.slice(0, 3).map(u => triggerTestAlarm(u)));
        await Promise.all(users.slice(0, 3).map(u => endActiveAlarms(u)));
      });
    }
  } finally {
    if (!args.keep && userIds.length) {
      console.log('\n== Cleanup ==');
      await step('testusers verwijderen', async () => {
        const r = await cleanupUserIds(userIds);
        ok(r.left === 0, `Cleanup incompleet, left=${r.left}`, r);
      });
    } else if (args.keep) {
      console.log(`\n--keep: users blijven staan (run ${runId}). Opruimen: npm run cleanup`);
    }
  }

  const { fail } = summary();
  process.exit(fail ? 1 : 0);
}

main().catch(err => {
  console.error('Suite crash:', err);
  process.exit(1);
});
