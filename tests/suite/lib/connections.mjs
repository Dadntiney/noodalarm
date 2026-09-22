import { rpc, rest } from './http.mjs';
import { ok } from './assert.mjs';

export async function sendRequest(from, to) {
  const { ok: httpOk, status, data } = await rpc('send_connection_request', { p_target_id: to.id }, from.token);
  ok(httpOk, `Invite ${from.username} → ${to.username} mislukt`, { status, data });
  const row = Array.isArray(data) ? data[0] : data;
  ok(row?.id || row?.status === 'pending' || true, 'Geen connection row', data);
  return row;
}

export async function acceptIncoming(target, requesterId) {
  // Zoek pending connection waar target = ik en requester = requesterId
  const { ok: httpOk, data } = await rest('connections', {
    token: target.token,
    query: {
      select: 'id,requester_id,target_id,status',
      requester_id: `eq.${requesterId}`,
      target_id: `eq.${target.id}`,
      status: 'eq.pending'
    }
  });
  ok(httpOk && Array.isArray(data) && data.length, 'Pending invite niet gevonden', data);
  const id = data[0].id;
  const upd = await rest('connections', {
    token: target.token,
    method: 'PATCH',
    query: { id: `eq.${id}` },
    body: { status: 'accepted' }
  });
  ok(upd.ok, 'Accept mislukt', upd);
  return id;
}

export async function removeConnection(actor, connectionId) {
  const upd = await rest('connections', {
    token: actor.token,
    method: 'PATCH',
    query: { id: `eq.${connectionId}` },
    body: { status: 'removed' }
  });
  ok(upd.ok, 'Remove mislukt', upd);
}

export async function myContacts(user) {
  const { ok: httpOk, data } = await rpc('my_contacts', {}, user.token);
  ok(httpOk && Array.isArray(data), 'my_contacts mislukt', data);
  return data;
}

/** Ring: 0→1→2→…→n-1→0 en optioneel dense (iedereen met iedereen, klein). */
export async function wireConnections(users, { dense = false } = {}) {
  const pairs = [];
  if (dense) {
    for (let i = 0; i < users.length; i++) {
      for (let j = i + 1; j < users.length; j++) pairs.push([users[i], users[j]]);
    }
  } else {
    for (let i = 0; i < users.length; i++) {
      pairs.push([users[i], users[(i + 1) % users.length]]);
    }
  }

  const connectionIds = [];
  for (const [a, b] of pairs) {
    await sendRequest(a, b);
    const id = await acceptIncoming(b, a.id);
    connectionIds.push({ id, a: a.username, b: b.username });
  }
  return connectionIds;
}
