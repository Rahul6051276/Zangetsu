-- Keep NULL distinct from an intentionally cleared bio so older app versions
-- cannot erase a newer profile bio when they upsert their older row shape.
alter table sync_api.viewer_profiles
  add column if not exists bio text
    check (char_length(bio) <= 160);

create or replace function sync_private.preserve_viewer_profile_bio()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.bio := coalesce(new.bio, old.bio);
  return new;
end;
$$;
revoke all on function sync_private.preserve_viewer_profile_bio() from public;

drop trigger if exists preserve_viewer_profile_bio on sync_api.viewer_profiles;
create trigger preserve_viewer_profile_bio
before update on sync_api.viewer_profiles
for each row execute function sync_private.preserve_viewer_profile_bio();

notify pgrst, 'reload schema';
