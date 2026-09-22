import { config, functionsUrl } from './config.mjs';

export async function edge(name, { token, body, method = 'POST' } = {}) {
  const headers = {
    apikey: config.anonKey,
    'Content-Type': 'application/json'
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  else headers.Authorization = `Bearer ${config.anonKey}`;

  const res = await fetch(functionsUrl(name), {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body)
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

export async function rest(path, { token, method = 'GET', body, query } = {}) {
  const url = new URL(`${config.supabaseUrl}/rest/v1/${path}`);
  if (query) {
    for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  }
  const headers = {
    apikey: config.anonKey,
    Authorization: `Bearer ${token || config.anonKey}`,
    'Content-Type': 'application/json',
    Prefer: method === 'POST' || method === 'PATCH' ? 'return=representation' : 'return=minimal'
  };
  if (method === 'POST' || method === 'PATCH') headers.Prefer = 'return=representation';

  const res = await fetch(url, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body)
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

export async function rpc(fn, args, token) {
  const res = await fetch(`${config.supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(args || {})
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  return { ok: res.ok, status: res.status, data };
}

/** Management API SQL (service-achtig). Vereist SUPABASE_ACCESS_TOKEN. */
export async function adminSql(query) {
  if (!config.accessToken) {
    throw new Error('SUPABASE_ACCESS_TOKEN ontbreekt (.env.local of env) — nodig voor cleanup');
  }
  const res = await fetch(`https://api.supabase.com/v1/projects/${config.projectRef}/database/query`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${config.accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ query })
  });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = { raw: text }; }
  if (!res.ok) {
    const msg = data?.message || text || res.statusText;
    throw new Error(`adminSql ${res.status}: ${msg}`);
  }
  return data;
}
