begin;
insert into sync_api.viewer_profiles (user_key, profile_id, name)
values ('cascade-test', 'viewer', 'Viewer');
insert into sync_api.profile_history
  (user_key, profile_id, source_id, show_id)
values ('cascade-test', 'viewer', 'source', 'show');
insert into sync_api.profile_reading_history
  (user_key, profile_id, source_id, show_id)
values ('cascade-test', 'viewer', 'source', 'show');
insert into sync_api.profile_mylist
  (user_key, profile_id, source_id, item_id)
values ('cascade-test', 'viewer', 'source', 'item');
insert into sync_api.mylist_sync_clock (user_key, profile_scope, version)
values ('cascade-test', 'viewer', 1)
on conflict (user_key, profile_scope) do update set version = excluded.version;
insert into sync_api.mylist_sync_tombstones
  (user_key, profile_scope, source_id, item_id, sync_version)
values ('cascade-test', 'viewer', 'source', 'deleted-item', 2);
insert into sync_api.profile_list_categories
  (user_key, profile_id, id, name)
values ('cascade-test', 'viewer', '11111111-1111-4111-8111-111111111111', 'Saved');
insert into sync_api.profile_mylist_categories
  (user_key, profile_id, source_id, item_id, category_id)
values ('cascade-test', 'viewer', 'source', 'item',
  '11111111-1111-4111-8111-111111111111');

delete from sync_api.viewer_profiles
where user_key = 'cascade-test' and profile_id = 'viewer';
set constraints all immediate;

do $$
begin
  if exists (select 1 from sync_api.profile_history
    where user_key = 'cascade-test')
    or exists (select 1 from sync_api.profile_reading_history
      where user_key = 'cascade-test')
    or exists (select 1 from sync_api.profile_mylist
      where user_key = 'cascade-test')
    or exists (select 1 from sync_api.profile_list_categories
      where user_key = 'cascade-test')
    or exists (select 1 from sync_api.profile_mylist_categories
      where user_key = 'cascade-test') then
    raise exception 'profile child data survived profile deletion';
  end if;
  if exists (select 1 from sync_api.mylist_sync_clock
    where user_key = 'cascade-test' and profile_scope = 'viewer')
    or exists (select 1 from sync_api.mylist_sync_tombstones
      where user_key = 'cascade-test' and profile_scope = 'viewer') then
    raise exception 'profile sync state survived profile deletion';
  end if;
end;
$$;

do $$
begin
  begin
    insert into sync_api.profile_reading_history
      (user_key, profile_id, source_id, show_id)
    values ('cascade-test', 'missing', 'source', 'orphan');
  exception when foreign_key_violation then
    return;
  end;
  raise exception 'profile child accepted without a viewer profile';
end;
$$;
rollback;
