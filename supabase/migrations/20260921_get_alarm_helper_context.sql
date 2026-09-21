-- Helpers ontvangen het NORI-alarmbericht in HUN eigen groep, maar zijn
-- niet altijd lid van de activator-groep. Deze RPC geeft veilig genoeg
-- context (actief? omw?) zodat Berichten de OMW-knop kan tonen zonder
-- de alarms-tabel RLS te omzeilen voor willekeurige rijen.

create or replace function public.get_alarm_helper_context(p_alarm_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a record;
  v_uid uuid := auth.uid();
  v_allowed boolean := false;
  v_omw timestamptz;
begin
  if v_uid is null or p_alarm_id is null then
    return null;
  end if;

  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    return null;
  end if;

  if v_uid = a.triggered_by then
    v_allowed := true;
  elsif not coalesce(a.test_mode, false) then
    select exists (
      select 1 from public.connections c
      where c.status = 'accepted'
        and (
          (c.requester_id = a.triggered_by and c.target_id = v_uid)
          or (c.target_id = a.triggered_by and c.requester_id = v_uid)
        )
    ) into v_allowed;
  end if;

  if not v_allowed then
    return null;
  end if;

  select n.omw_at into v_omw
  from public.notifications n
  where n.user_id = v_uid
    and n.type = 'alarm'
    and n.related_alarm_id = p_alarm_id
  order by n.created_at desc
  limit 1;

  return jsonb_build_object(
    'id', a.id,
    'status', a.status,
    'triggered_by', a.triggered_by,
    'test_mode', coalesce(a.test_mode, false),
    'lat', a.lat,
    'lng', a.lng,
    'location_accuracy', a.location_accuracy,
    'location_updated_at', a.location_updated_at,
    'created_at', a.created_at,
    'omw_done', v_omw is not null,
    'is_activator', v_uid = a.triggered_by
  );
end;
$$;

revoke all on function public.get_alarm_helper_context(uuid) from public;
grant execute on function public.get_alarm_helper_context(uuid) to authenticated;
