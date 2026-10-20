-- Keep NULL distinct from an intentionally removed cover. Older app versions
-- omit cover_url from upserts, so their writes must not erase newer artwork.
alter table sync_api.viewer_profiles
  add column if not exists cover_url text
    check (char_length(cover_url) <= 2048);

create or replace function sync_private.preserve_viewer_profile_cover()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.cover_url := coalesce(new.cover_url, old.cover_url);
  return new;
end;
$$;
revoke all on function sync_private.preserve_viewer_profile_cover() from public;

drop trigger if exists preserve_viewer_profile_cover on sync_api.viewer_profiles;
create trigger preserve_viewer_profile_cover
before update on sync_api.viewer_profiles
for each row execute function sync_private.preserve_viewer_profile_cover();

notify pgrst, 'reload schema';
