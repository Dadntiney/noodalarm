-- Locatie staat live bovenaan Berichten; NORI-bericht houdt alleen
-- de reddingskaart-knop (token). Maps-URL uit de body gehaald.

create or replace function public.nori_alarm_rescue_message_body(p_alarm_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a record;
  v_name text;
  v_body text;
begin
  select * into a from public.alarms where id = p_alarm_id;
  if a.id is null then
    return null;
  end if;

  select full_name into v_name from public.profiles where id = a.triggered_by;
  v_name := coalesce(nullif(trim(v_name), ''), 'Iemand');

  v_body := '🚨 Alarm van ' || v_name || E'\n\n';
  v_body := v_body || '🩺 nori-rescue:' || a.id::text;

  if char_length(v_body) > 1000 then
    v_body := left(v_body, 997) || '…';
  end if;
  return v_body;
end;
$$;
