-- My List and its categories on the unpublished VPS stage. Auth stays Supabase.
create table if not exists sync_api.mylist (
  user_key text not null,
  source_id text not null,
  item_id text not null,
  title text not null default '',
  cover text,
  cover_headers jsonb,
  url text,
  type text,
  status text,
  added_at bigint not null default 0,
  sync_id bigint generated always as identity,
  sync_version bigint not null default 0,
  primary key (user_key, source_id, item_id),
  unique (user_key, sync_id)
);
create index if not exists mylist_sync_version_idx
  on sync_api.mylist (user_key, sync_version);

create table if not exists sync_api.profile_mylist (
  user_key text not null,
  profile_id text not null,
  source_id text not null,
  item_id text not null,
  title text not null default '',
  cover text,
  cover_headers jsonb,
  url text,
  type text,
  status text,
  added_at bigint not null default 0,
  sync_id bigint generated always as identity,
  sync_version bigint not null default 0,
  primary key (user_key, profile_id, source_id, item_id),
  unique (user_key, profile_id, sync_id)
);
create index if not exists profile_mylist_sync_version_idx
  on sync_api.profile_mylist (user_key, profile_id, sync_version);

create table if not exists sync_api.mylist_sync_clock (
  user_key text not null,
  profile_scope text not null default '',
  version bigint not null default 0,
  primary key (user_key, profile_scope)
);
create table if not exists sync_api.mylist_sync_tombstones (
  user_key text not null,
  profile_scope text not null default '',
  source_id text not null,
  item_id text not null,
  sync_version bigint not null,
  primary key (user_key, profile_scope, source_id, item_id)
);
create index if not exists mylist_sync_tombstones_version_idx
  on sync_api.mylist_sync_tombstones
  (user_key, profile_scope, sync_version);

create table if not exists sync_api.list_categories (
  id uuid primary key default gen_random_uuid(),
  user_key text not null,
  name text not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  unique (user_key, name)
);
create table if not exists sync_api.mylist_categories (
  user_key text not null,
  source_id text not null,
  item_id text not null,
  category_id uuid not null references sync_api.list_categories(id)
    on delete cascade,
  primary key (user_key, source_id, item_id, category_id)
);
create table if not exists sync_api.profile_list_categories (
  user_key text not null,
  profile_id text not null,
  id uuid not null default gen_random_uuid(),
  name text not null,
  position integer not null default 0,
  primary key (user_key, profile_id, id)
);
create table if not exists sync_api.profile_mylist_categories (
  user_key text not null,
  profile_id text not null,
  source_id text not null,
  item_id text not null,
  category_id uuid not null,
  primary key (user_key, profile_id, source_id, item_id, category_id),
  foreign key (user_key, profile_id, category_id)
    references sync_api.profile_list_categories(user_key, profile_id, id)
    on delete cascade
);

create or replace function sync_private.bump_mylist_sync_version()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner_key text := to_jsonb(new) ->> 'user_key';
  profile_key text := coalesce(to_jsonb(new) ->> 'profile_id', '');
  next_version bigint;
begin
  insert into sync_api.mylist_sync_clock(user_key, profile_scope, version)
  values (owner_key, profile_key, 1)
  on conflict (user_key, profile_scope) do update
    set version = sync_api.mylist_sync_clock.version + 1
  returning version into next_version;
  new.sync_version := next_version;
  return new;
end;
$$;
create or replace function sync_private.clear_mylist_sync_tombstone()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from sync_api.mylist_sync_tombstones
  where user_key = to_jsonb(new) ->> 'user_key'
    and profile_scope = coalesce(to_jsonb(new) ->> 'profile_id', '')
    and source_id = new.source_id and item_id = new.item_id;
  return new;
end;
$$;
create or replace function sync_private.record_mylist_sync_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  owner_key text := to_jsonb(old) ->> 'user_key';
  profile_key text := coalesce(to_jsonb(old) ->> 'profile_id', '');
  next_version bigint;
begin
  if pg_trigger_depth() > 1 then return old; end if;
  insert into sync_api.mylist_sync_clock(user_key, profile_scope, version)
  values (owner_key, profile_key, 1)
  on conflict (user_key, profile_scope) do update
    set version = sync_api.mylist_sync_clock.version + 1
  returning version into next_version;
  insert into sync_api.mylist_sync_tombstones
    (user_key, profile_scope, source_id, item_id, sync_version)
  values (owner_key, profile_key, old.source_id, old.item_id, next_version)
  on conflict (user_key, profile_scope, source_id, item_id) do update
    set sync_version = excluded.sync_version;
  return old;
end;
$$;
revoke all on function sync_private.bump_mylist_sync_version() from public;
revoke all on function sync_private.clear_mylist_sync_tombstone() from public;
revoke all on function sync_private.record_mylist_sync_delete() from public;

drop trigger if exists mylist_sync_version on sync_api.mylist;
create trigger mylist_sync_version before insert or update on sync_api.mylist
  for each row execute function sync_private.bump_mylist_sync_version();
drop trigger if exists mylist_sync_clear_tombstone on sync_api.mylist;
create trigger mylist_sync_clear_tombstone after insert or update
  on sync_api.mylist for each row
  execute function sync_private.clear_mylist_sync_tombstone();
drop trigger if exists mylist_sync_delete on sync_api.mylist;
create trigger mylist_sync_delete after delete on sync_api.mylist
  for each row execute function sync_private.record_mylist_sync_delete();
drop trigger if exists profile_mylist_sync_version on sync_api.profile_mylist;
create trigger profile_mylist_sync_version before insert or update
  on sync_api.profile_mylist for each row
  execute function sync_private.bump_mylist_sync_version();
drop trigger if exists profile_mylist_sync_clear_tombstone
  on sync_api.profile_mylist;
create trigger profile_mylist_sync_clear_tombstone after insert or update
  on sync_api.profile_mylist for each row
  execute function sync_private.clear_mylist_sync_tombstone();
drop trigger if exists profile_mylist_sync_delete on sync_api.profile_mylist;
create trigger profile_mylist_sync_delete after delete on sync_api.profile_mylist
  for each row execute function sync_private.record_mylist_sync_delete();

alter table sync_api.mylist enable row level security;
alter table sync_api.mylist force row level security;
alter table sync_api.profile_mylist enable row level security;
alter table sync_api.profile_mylist force row level security;
alter table sync_api.list_categories enable row level security;
alter table sync_api.list_categories force row level security;
alter table sync_api.profile_list_categories enable row level security;
alter table sync_api.profile_list_categories force row level security;
alter table sync_api.mylist_categories enable row level security;
alter table sync_api.mylist_categories force row level security;
alter table sync_api.profile_mylist_categories enable row level security;
alter table sync_api.profile_mylist_categories force row level security;
alter table sync_api.mylist_sync_clock enable row level security;
alter table sync_api.mylist_sync_clock force row level security;
alter table sync_api.mylist_sync_tombstones enable row level security;
alter table sync_api.mylist_sync_tombstones force row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'mylist', 'profile_mylist', 'list_categories',
    'profile_list_categories', 'mylist_categories',
    'profile_mylist_categories'
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
drop policy if exists own_clock on sync_api.mylist_sync_clock;
create policy own_clock on sync_api.mylist_sync_clock for select
  to authenticated using (user_key = sync_private.jwt_user_key());
drop policy if exists own_tombstones on sync_api.mylist_sync_tombstones;
create policy own_tombstones on sync_api.mylist_sync_tombstones for select
  to authenticated using (user_key = sync_private.jwt_user_key());
grant select on sync_api.mylist_sync_clock,
  sync_api.mylist_sync_tombstones to authenticated;
