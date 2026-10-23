-- Theme preferences belong to a viewer profile and are optional so profiles
-- created by older app versions keep the existing device appearance.
alter table sync_api.viewer_profiles
  add column if not exists accent_color bigint
    check (accent_color between 0 and 4294967295),
  add column if not exists material_you boolean,
  add column if not exists amoled boolean;

create or replace function sync_private.preserve_viewer_profile_theme()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Older clients omit these fields; do not erase newer clients' choices.
  new.accent_color := coalesce(new.accent_color, old.accent_color);
  new.material_you := coalesce(new.material_you, old.material_you);
  new.amoled := coalesce(new.amoled, old.amoled);
  return new;
end;
$$;
revoke all on function sync_private.preserve_viewer_profile_theme() from public;

drop trigger if exists preserve_viewer_profile_theme on sync_api.viewer_profiles;
create trigger preserve_viewer_profile_theme
before update on sync_api.viewer_profiles
for each row execute function sync_private.preserve_viewer_profile_theme();

notify pgrst, 'reload schema';
