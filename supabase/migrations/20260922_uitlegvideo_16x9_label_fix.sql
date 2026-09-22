-- Gebruikersvriendelijke release note voor de uitlegvideo-weergavefix.
insert into public.release_notes (message_nl)
select 'De uitlegvideo in Berichten blijft netjes in beeld: de titel NORI Uitleg is goed leesbaar, en na het afspelen heeft de video weer precies dezelfde vorm als ervoor.'
where not exists (
  select 1 from public.release_notes
  where message_nl like 'De uitlegvideo in Berichten blijft netjes in beeld%'
);
