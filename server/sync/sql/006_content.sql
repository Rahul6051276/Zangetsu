-- Reading history, viewer profiles, and backups on the unpublished VPS stage.
-- Auth stays Supabase; these tables only mirror the Supabase schema so the
-- same app code and the same RLS rules run unchanged.

create table if not exists sync_api.reading_history (
  user_key text not null,
  source_id text not null,
  show_id text not null,
  title text not null default '',
  cover text,
  chapter_id text,
  chapter_number double precision,
  chapter_url text,
  pos integer not null default 0,
  total integer not null default 0,
  updated_ms bigint not null default 0,
  type text,
  primary key (user_key, source_id, show_id)
);
create index if not exists reading_history_recent_by_user
  on sync_api.reading_history (user_key, updated_ms desc, source_id, show_id);

create table if not exists sync_api.profile_reading_history (
  user_key text not null,
  profile_id text not null,
  source_id text not null,
  show_id text not null,
  title text not null default '',
  cover text,
  chapter_id text,
  chapter_number double precision,
  chapter_url text,
  pos integer not null default 0,
  total integer not null default 0,
  updated_ms bigint not null default 0,
  type text,
  primary key (user_key, profile_id, source_id, show_id)
);
create index if not exists profile_reading_history_recent_by_user
  on sync_api.profile_reading_history
  (user_key, profile_id, updated_ms desc, source_id, show_id);

create table if not exists sync_api.viewer_profiles (
  user_key text not null,
  profile_id text not null,
  name text not null check (char_length(btrim(name)) between 1 and 24),
  avatar integer not null default 0 check (avatar between 0 and 11),
  is_kids boolean not null default false,
  created_at timestamptz not null default now(),
  photo_url text,
  primary key (user_key, profile_id)
);

create table if not exists sync_api.backups (
  user_key text primary key,
  payload text not null,
  updated_at timestamptz not null default now()
);

-- Same four-profile cap as public.enforce_viewer_profile_limit() so the app
-- cannot create a fifth profile on either backend.
create or replace function sync_private.enforce_viewer_profile_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext(new.user_key), 0);
  if not exists (
    select 1 from sync_api.viewer_profiles
    where user_key = new.user_key and profile_id = new.profile_id
  ) and (
    select count(*) from sync_api.viewer_profiles where user_key = new.user_key
  ) >= 4 then
    raise exception 'A maximum of four profiles is allowed per account';
  end if;
  return new;
end;
$$;
revoke all on function sync_private.enforce_viewer_profile_limit() from public;

drop trigger if exists viewer_profile_limit on sync_api.viewer_profiles;
create trigger viewer_profile_limit before insert on sync_api.viewer_profiles
  for each row execute function sync_private.enforce_viewer_profile_limit();

alter table sync_api.reading_history enable row level security;
alter table sync_api.reading_history force row level security;
alter table sync_api.profile_reading_history enable row level security;
alter table sync_api.profile_reading_history force row level security;
alter table sync_api.viewer_profiles enable row level security;
alter table sync_api.viewer_profiles force row level security;
alter table sync_api.backups enable row level security;
alter table sync_api.backups force row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'reading_history', 'profile_reading_history', 'viewer_profiles', 'backups'
  ] loop
    execute format('drop policy if exists own_rows on sync_api.%I', table_name);
    execute format(
      'create policy own_rows on sync_api.%I for all to authenticated '
      'using (user_key = sync_private.jwt_user_key()) '
      'with check (user_key = sync_private.jwt_user_key())', table_name
    );
    execute format('grant select, insert, update, delete on sync_api.%I '
      'to authenticated', table_name);
  end loop;
end;
$$;
