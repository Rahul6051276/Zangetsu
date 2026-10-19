-- Local-socket bridge role. No password, so TCP password authentication fails.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'zangetsu_bridge') then
    create role zangetsu_bridge login noinherit;
  end if;
end;
$$;

grant usage on schema sync_api, sync_private to zangetsu_bridge;
grant select, insert, update, delete on
  sync_api.history, sync_api.profile_history to zangetsu_bridge;
grant select, delete on sync_private.history_bridge_events to zangetsu_bridge;
grant select, insert, update, delete on
  sync_private.history_bridge_cursors,
  sync_private.history_bridge_latest to zangetsu_bridge;

drop policy if exists bridge_history on sync_api.history;
create policy bridge_history on sync_api.history
  for all to zangetsu_bridge using (true) with check (true);
drop policy if exists bridge_profile_history on sync_api.profile_history;
create policy bridge_profile_history on sync_api.profile_history
  for all to zangetsu_bridge using (true) with check (true);

-- App writes keep the existing newer-progress guard. Only a replay from the
-- dedicated bridge role may apply the centrally chosen winning event.
create or replace function sync_private.keep_newer_history()
returns trigger
language plpgsql
as $$
begin
  if session_user = 'zangetsu_bridge'
      and current_setting('zangetsu.bridge_replay', true) = 'on' then
    return new;
  end if;
  if old.updated_at > new.updated_at then
    return old;
  end if;
  return new;
end;
$$;
