-- Als een alarm eindigt: NORI-alarmberichten (locatie + reddingskaart)
-- uit alle chats verwijderen. Ze horen alleen alleenbaar te zijn zolang
-- het alarm actief is.

create or replace function public.cleanup_nori_messages_on_alarm_end()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'ended' and coalesce(old.status, '') is distinct from 'ended' then
    delete from public.alarm_messages
    where alarm_id = new.id
      and sender_id = public.nori_system_user_id();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cleanup_nori_messages_on_alarm_end on public.alarms;
create trigger trg_cleanup_nori_messages_on_alarm_end
  after update of status on public.alarms
  for each row
  execute function public.cleanup_nori_messages_on_alarm_end();

-- Eenmalig: oude NORI-alarmberichten van reeds beëindigde alarms weg.
delete from public.alarm_messages m
using public.alarms a
where m.alarm_id = a.id
  and m.sender_id = public.nori_system_user_id()
  and a.status is distinct from 'active';
