-- Run against disposable/staging VPS DB after 001_watch_history.sql.
-- The transaction leaves no data behind.
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"bridge-test-user"}', true);

insert into sync_api.history (
  user_key, source_id, show_id, show_title, updated_at
) values (
  'bridge-test-user', 'bridge-test-source', 'bridge-test-show', 'first', 100
);

reset role;
do $$
begin
  if (select count(*) from sync_private.history_bridge_events
      where user_key = 'bridge-test-user'
        and source_id = 'bridge-test-source'
        and show_id = 'bridge-test-show'
        and operation = 'upsert') <> 1 then
    raise exception 'history upsert did not create exactly one bridge event';
  end if;
end;
$$;

set local role authenticated;
delete from sync_api.history
where user_key = 'bridge-test-user'
  and source_id = 'bridge-test-source'
  and show_id = 'bridge-test-show';

reset role;
do $$
begin
  if (select count(*) from sync_private.history_bridge_events
      where user_key = 'bridge-test-user'
        and source_id = 'bridge-test-source'
        and show_id = 'bridge-test-show'
        and operation = 'delete') <> 1 then
    raise exception 'history delete did not create exactly one tombstone event';
  end if;
end;
$$;
rollback;
