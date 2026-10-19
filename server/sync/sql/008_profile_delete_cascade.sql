-- Match Supabase profile deletion: remove every profile-scoped cloud row.
-- Refuse to attach the constraint if the stage copy is missing any parent.
do $$
declare
  child_table text;
  orphan_exists boolean;
begin
  foreach child_table in array array[
    'profile_history', 'profile_reading_history', 'profile_mylist',
    'profile_list_categories', 'profile_mylist_categories'
  ] loop
    execute format(
      'select exists (select 1 from sync_api.%I child '
      'left join sync_api.viewer_profiles parent '
      'on parent.user_key = child.user_key '
      'and parent.profile_id = child.profile_id '
      'where parent.user_key is null)', child_table
    ) into orphan_exists;
    if orphan_exists then
      raise exception 'missing viewer profile for rows in %', child_table;
    end if;
    if not exists (
      select 1 from pg_constraint
      where conrelid = format('sync_api.%I', child_table)::regclass
        and conname = 'profile_owner_cascade'
    ) then
      execute format(
        'alter table sync_api.%I add constraint profile_owner_cascade '
        'foreign key (user_key, profile_id) '
        'references sync_api.viewer_profiles(user_key, profile_id) '
        'on delete cascade', child_table
      );
    end if;
  end loop;
end;
$$;
