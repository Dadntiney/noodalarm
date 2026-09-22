import { config } from './config.mjs';
import { ok } from './assert.mjs';

async function upsert(table, user, row) {
  const res = await fetch(
    `${config.supabaseUrl}/rest/v1/${table}?on_conflict=user_id`,
    {
      method: 'POST',
      headers: {
        apikey: config.anonKey,
        Authorization: `Bearer ${user.token}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=representation'
      },
      body: JSON.stringify(row)
    }
  );
  const data = await res.json().catch(() => null);
  ok(res.ok, `${table} upsert mislukt`, data);
  return data;
}

export async function upsertMedicalMerge(user) {
  const now = new Date().toISOString();
  return upsert('medical_info', user, {
    user_id: user.id,
    allergies: 'suite-test pinda',
    mobility: 'good',
    consent_given_at: now,
    updated_at: now
  });
}

export async function upsertPractical(user) {
  const now = new Date().toISOString();
  return upsert('practical_info', user, {
    user_id: user.id,
    spare_key_location: 'suite: kluisje test',
    updated_at: now
  });
}
