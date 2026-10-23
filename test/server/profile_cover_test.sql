begin;
insert into sync_api.viewer_profiles (user_key, profile_id, name, cover_url)
values ('cover-test', 'viewer', 'Viewer', 'https://example.com/cover.jpg');

-- Older apps omit cover_url when editing the same profile.
insert into sync_api.viewer_profiles (user_key, profile_id, name)
values ('cover-test', 'viewer', 'Renamed')
on conflict (user_key, profile_id) do update
set name = excluded.name, cover_url = excluded.cover_url;

do $$
begin
  if (select cover_url from sync_api.viewer_profiles
      where user_key = 'cover-test' and profile_id = 'viewer')
      is distinct from 'https://example.com/cover.jpg' then
    raise exception 'an older profile write erased the cover';
  end if;
end;
$$;

-- The new client sends an empty string to clear a cover deliberately.
insert into sync_api.viewer_profiles (user_key, profile_id, name, cover_url)
values ('cover-test', 'viewer', 'Renamed', '')
on conflict (user_key, profile_id) do update set cover_url = excluded.cover_url;

do $$
begin
  if (select cover_url from sync_api.viewer_profiles
      where user_key = 'cover-test' and profile_id = 'viewer')
      is distinct from '' then
    raise exception 'the new client could not clear the cover';
  end if;
end;
$$;
rollback;
