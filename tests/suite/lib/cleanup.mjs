import { adminSql } from './http.mjs';
import { config } from './config.mjs';

/**
 * Verwijdert suite-users veilig in FK-volgorde.
 * @param {string[]} userIds
 */
export async function cleanupUserIds(userIds) {
  if (!userIds.length) return { deleted: 0 };
  const list = userIds.map(id => `'${id}'::uuid`).join(',');

  const steps = [
    `DELETE FROM message_receipts
      WHERE user_id IN (${list})
         OR group_id IN (SELECT id FROM alarm_groups WHERE owner_id IN (${list}))
         OR message_id IN (
              SELECT id FROM alarm_messages
               WHERE sender_id IN (${list})
                  OR group_id IN (SELECT id FROM alarm_groups WHERE owner_id IN (${list}))
            );`,
    `DELETE FROM alarm_messages
      WHERE sender_id IN (${list})
         OR group_id IN (SELECT id FROM alarm_groups WHERE owner_id IN (${list}));`,
    `DELETE FROM notifications
      WHERE user_id IN (${list})
         OR related_alarm_id IN (SELECT id FROM alarms WHERE triggered_by IN (${list}));`,
    `DELETE FROM alarms WHERE triggered_by IN (${list});`,
    `DELETE FROM connections WHERE requester_id IN (${list}) OR target_id IN (${list});`,
    `DELETE FROM alarm_group_members
      WHERE user_id IN (${list})
         OR group_id IN (SELECT id FROM alarm_groups WHERE owner_id IN (${list}));`,
    `DELETE FROM alarm_groups WHERE owner_id IN (${list});`,
    `DELETE FROM medical_info WHERE user_id IN (${list});`,
    `DELETE FROM practical_info WHERE user_id IN (${list});`,
    `DELETE FROM push_subscriptions WHERE user_id IN (${list});`,
    `DELETE FROM profiles WHERE id IN (${list});`,
    `DELETE FROM auth.users WHERE id IN (${list});`
  ];

  for (const q of steps) await adminSql(q);
  const left = await adminSql(`SELECT count(*)::int AS n FROM auth.users WHERE id IN (${list});`);
  return { deleted: userIds.length, left: left?.[0]?.n ?? null };
}

/** Alle users met username prefix lt* (of custom). */
export async function cleanupByPrefix(prefix = config.prefix) {
  const rows = await adminSql(
    `SELECT id::text AS id, username FROM profiles WHERE username LIKE '${prefix.replace(/'/g, "''")}%' AND coalesce(is_system,false) = false;`
  );
  const ids = (rows || []).map(r => r.id);
  if (!ids.length) return { deleted: 0, usernames: [] };
  const result = await cleanupUserIds(ids);
  return { ...result, usernames: (rows || []).map(r => r.username) };
}
