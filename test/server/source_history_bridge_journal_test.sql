-- Run against a disposable database after source_history_bridge_setup.sql.
begin;
insert into public.history (user_key, source_id, show_id, updated_at)
values ('bridge-test-user', 'source', 'show', 100);

do $$
begin
  if (select count(*) from sync_private.history_bridge_events
      where user_key = 'bridge-test-user' and operation = 'upsert') <> 1 then
    raise exception 'source upsert was not journaled once';
  end if;
end;
$$;

delete from public.history
where user_key = 'bridge-test-user' and source_id = 'source'
  and show_id = 'show';

do $$
begin
  if (select count(*) from sync_private.history_bridge_events
      where user_key = 'bridge-test-user' and operation = 'delete') <> 1 then
    raise exception 'source delete was not journaled once';
  end if;
end;
$$;

insert into public.profile_history
  (user_key, profile_id, source_id, show_id, updated_at)
values ('bridge-test-user', 'child', 'source', 'show', 100);

do $$
begin
  if (select count(*) from sync_private.history_bridge_events
      where user_key = 'bridge-test-user' and profile_id = 'child'
        and operation = 'upsert') <> 1 then
    raise exception 'profile source upsert was not journaled';
  end if;
end;
$$;
rollback;
