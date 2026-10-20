begin;
insert into sync_api.viewer_profiles (user_key, profile_id, name, bio)
values ('bio-test', 'viewer', 'Viewer', 'Reading manga');

-- An old client omits bio while updating its known profile fields.
insert into sync_api.viewer_profiles (user_key, profile_id, name)
values ('bio-test', 'viewer', 'Renamed')
on conflict (user_key, profile_id) do update
set name = excluded.name, bio = excluded.bio;

do $$
begin
  if (select bio from sync_api.viewer_profiles
      where user_key = 'bio-test' and profile_id = 'viewer')
      is distinct from 'Reading manga' then
    raise exception 'an older profile write erased the bio';
  end if;
end;
$$;

insert into sync_api.viewer_profiles (user_key, profile_id, name, bio)
values ('bio-test', 'viewer', 'Renamed', '')
on conflict (user_key, profile_id) do update
set bio = excluded.bio;

do $$
begin
  if (select bio from sync_api.viewer_profiles
      where user_key = 'bio-test' and profile_id = 'viewer')
      is distinct from '' then
    raise exception 'the new client could not clear the bio';
  end if;
end;
$$;

do $$
begin
  begin
    update sync_api.viewer_profiles set bio = repeat('x', 161)
    where user_key = 'bio-test' and profile_id = 'viewer';
  exception when check_violation then
    return;
  end;
  raise exception 'overlong bio was accepted';
end;
$$;
rollback;
