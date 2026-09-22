import { edge, rpc, rest } from './http.mjs';
import { ok } from './assert.mjs';

export async function triggerTestAlarm(user, { lat = 51.84, lng = 5.86, accuracy = 12 } = {}) {
  const { ok: httpOk, status, data } = await edge('send-alert', {
    token: user.token,
    body: { testMode: true, lat, lng, accuracy }
  });
  ok(httpOk && data?.alarmId, `send-alert (test) mislukt voor ${user.username}`, { status, data });
  return data;
}

export async function triggerAlarmRpc(user, { testMode = true, lat = 51.84, lng = 5.86, accuracy = 12 } = {}) {
  const { ok: httpOk, status, data } = await rpc('trigger_alarm', {
    p_test_mode: testMode,
    p_lat: lat,
    p_lng: lng,
    p_accuracy: accuracy
  }, user.token);
  ok(httpOk, `trigger_alarm mislukt voor ${user.username}`, { status, data });
  return data;
}

export async function endActiveAlarms(user) {
  const { ok: httpOk, data } = await rest('alarms', {
    token: user.token,
    method: 'PATCH',
    query: {
      triggered_by: `eq.${user.id}`,
      status: 'eq.active'
    },
    body: { status: 'ended' }
  });
  ok(httpOk, `Alarm beëindigen mislukt voor ${user.username}`, data);
  return data;
}
