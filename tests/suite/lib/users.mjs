import { config } from './config.mjs';
import { edge, rpc, rest } from './http.mjs';
import { ok } from './assert.mjs';

/** Run-id: 4 hex chars → usernames blijven ≤20. */
export function makeRunId() {
  return Math.floor(Math.random() * 0xffff).toString(16).padStart(4, '0');
}

export function userSpec(runId, index) {
  const n = String(index).padStart(3, '0');
  const username = `${config.prefix}${runId}${n}`; // lt + 4 + 3 = 9
  return {
    index,
    username,
    email: `${username}@gmail.com`,
    first_name: `Lt${runId}`,
    last_name: `U${n}`,
    password: config.password
  };
}

export async function registerUser(spec) {
  const { ok: httpOk, status, data } = await edge('register', {
    body: {
      first_name: spec.first_name,
      last_name: spec.last_name,
      username: spec.username,
      email: spec.email,
      password: spec.password
    }
  });
  ok(httpOk && data?.access_token && data?.user?.id,
    `Register mislukt voor ${spec.username}`,
    { status, data });
  return {
    ...spec,
    id: data.user.id,
    token: data.access_token,
    refresh: data.refresh_token
  };
}

export async function loginUser(spec) {
  const { ok: httpOk, status, data } = await edge('login', {
    body: { identifier: spec.username, password: spec.password }
  });
  ok(httpOk && data?.access_token,
    `Login mislukt voor ${spec.username}`,
    { status, data });
  return { ...spec, id: data.user?.id || spec.id, token: data.access_token };
}

export async function ownGroupId(token) {
  const { ok: httpOk, data } = await rest('alarm_groups', {
    token,
    query: { select: 'id', limit: '1' }
  });
  ok(httpOk && Array.isArray(data) && data[0]?.id, 'Geen eigen alarm_group', data);
  return data[0].id;
}

export async function createUsers(count, { concurrency = 4 } = {}) {
  const runId = makeRunId();
  const specs = Array.from({ length: count }, (_, i) => userSpec(runId, i));
  const users = [];
  for (let i = 0; i < specs.length; i += concurrency) {
    const chunk = specs.slice(i, i + concurrency);
    const created = await Promise.all(chunk.map(registerUser));
    users.push(...created);
  }
  return { runId, users };
}
