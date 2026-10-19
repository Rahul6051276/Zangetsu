-- Run against VPS staging after 002_history_bridge.sql; rollback leaves no rows.
begin;
insert into sync_private.history_bridge_cursors (origin, last_id)
values ('supabase', 5)
on conflict (origin) do update set last_id = excluded.last_id;
insert into sync_private.history_bridge_latest (
  user_key, profile_scope, source_id, show_id, origin, event_id,
  operation, changed_at, row_data
) values (
  'bridge-state-test', '', 'source', 'show', 'supabase', 5,
  'delete', now(), null
);
do $$
begin
  if (select last_id from sync_private.history_bridge_cursors
      where origin = 'supabase') <> 5 then
    raise exception 'cursor was not durable';
  end if;
  if (select operation from sync_private.history_bridge_latest
      where user_key = 'bridge-state-test' and profile_scope = ''
        and source_id = 'source' and show_id = 'show') <> 'delete' then
    raise exception 'delete winner was not retained as a tombstone';
  end if;
end;
$$;
rollback;
