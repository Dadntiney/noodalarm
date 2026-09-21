import { rest } from './http.mjs';
import { ok } from './assert.mjs';
import { ownGroupId } from './users.mjs';

export async function sendChatMessage(user, body) {
  const groupId = await ownGroupId(user.token);
  const { ok: httpOk, status, data } = await rest('alarm_messages', {
    token: user.token,
    method: 'POST',
    body: {
      group_id: groupId,
      sender_id: user.id,
      body
    }
  });
  ok(httpOk && Array.isArray(data) && data[0]?.id,
    `Chatbericht mislukt voor ${user.username}`,
    { status, data });
  return data[0];
}
